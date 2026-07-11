# Worker-Pod Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional SSH, Playwright CLI, Camoufox CLI, browser skills, and GitHub CLI capabilities to the OpenCode Docker image while preserving non-root runtime operation and fast browser startup.

**Architecture:** Four independent Docker build arguments gate package installation. A small entrypoint conditionally starts a non-root sshd when `SSH_PUBLIC_KEY` is present, then execs the existing OpenCode command. Browser binaries and upstream skills are installed into the `opencode` user's home outside persistent config mounts.

**Tech Stack:** Docker/BuildKit, Debian bookworm, POSIX shell, OpenSSH, Node.js 24, `@playwright/cli`, Chromium, `camoufox-cli`, GitHub CLI, Docker Compose, GitHub Actions.

## Global Constraints

- Build arguments default to `true`: `INSTALL_SSH`, `INSTALL_PLAYWRIGHT`, `INSTALL_CAMOUFOX`, `INSTALL_GH`.
- Runtime user remains `opencode`; sshd listens on non-privileged port `2222`.
- SSH authentication is public-key only; no password or root login.
- Playwright installs Chromium only; Firefox and WebKit remain excluded.
- Camoufox and Chromium browser binaries are downloaded at image build time.
- Browser skills live under `/home/opencode/.agents/skills/`, outside mounted `.config`, `.local/share`, and `.local/state` paths.
- Browser integrations are CLI + skill only; no MCP server is configured.
- GitHub credentials are never copied into an image layer; authentication is runtime-only through `GH_TOKEN`, `GITHUB_TOKEN`, or `gh auth login`.
- The image must continue to build for `linux/amd64` and `linux/arm64`.

## File Structure

- `Dockerfile`: build arguments, conditional apt/npm/tool/browser/skill installation, runtime metadata, and entrypoint wiring.
- `docker-entrypoint.sh`: SSH key validation/setup, optional sshd launch, and foreground command execution.
- `sshd_config`: fixed non-root sshd policy and port configuration.
- `tests/docker-smoke.sh`: build-argument, binary, skill, browser, and runtime SSH smoke tests.
- `docker-compose.yml`: SSH port and runtime environment passthrough.
- `.env.sample`: safe examples for `SSH_PUBLIC_KEY` and `GH_TOKEN`.
- `README.md`: build options, SSH use, browser tooling, skills, and GitHub authentication.
- `.github/workflows/update-image.yml`: run smoke verification before publishing each architecture.

---

### Task 1: Conditional non-root SSH runtime

**Files:**
- Create: `docker-entrypoint.sh`
- Create: `sshd_config`
- Create: `tests/entrypoint-smoke.sh`
- Modify: `Dockerfile`

**Interfaces:**
- Consumes: `SSH_PUBLIC_KEY` environment variable and container command arguments.
- Produces: `/home/opencode/.ssh/authorized_keys`, user-owned host keys, optional sshd on port 2222, and `exec "$@"` behavior.

- [ ] **Step 1: Add a failing entrypoint smoke test**

Create `tests/entrypoint-smoke.sh`:

```sh
#!/bin/sh
set -eu

ENTRYPOINT=${ENTRYPOINT:-./docker-entrypoint.sh}
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/home"
cat >"$TMPDIR/bin/ssh-keygen" <<'EOF'
#!/bin/sh
touch "$TEST_HOME/.ssh/ssh_host_ed25519_key"
EOF
cat >"$TMPDIR/bin/sshd" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$TEST_HOME/sshd.args"
EOF
chmod +x "$TMPDIR/bin/ssh-keygen" "$TMPDIR/bin/sshd"

HOME="$TMPDIR/home" TEST_HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$PATH" \
  SSH_PUBLIC_KEY='ssh-ed25519 AAAATEST worker@test' \
  SSHD_CONFIG=/test/sshd_config \
  "$ENTRYPOINT" sh -c 'printf command-ran >"$HOME/command-ran"'

test "$(cat "$TMPDIR/home/.ssh/authorized_keys")" = 'ssh-ed25519 AAAATEST worker@test'
test "$(stat -c %a "$TMPDIR/home/.ssh")" = 700
test "$(stat -c %a "$TMPDIR/home/.ssh/authorized_keys")" = 600
test "$(cat "$TMPDIR/home/sshd.args")" = '-f /test/sshd_config'
test -f "$TMPDIR/home/command-ran"

rm -f "$TMPDIR/home/sshd.args"
HOME="$TMPDIR/home" TEST_HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$PATH" \
  SSH_PUBLIC_KEY='' "$ENTRYPOINT" true
test ! -e "$TMPDIR/home/sshd.args"
```

- [ ] **Step 2: Run the test and verify it fails before implementation**

Run: `chmod +x tests/entrypoint-smoke.sh && tests/entrypoint-smoke.sh`

Expected: FAIL because `./docker-entrypoint.sh` does not exist.

- [ ] **Step 3: Implement the entrypoint and sshd policy**

Create executable `docker-entrypoint.sh`:

```sh
#!/bin/sh
set -eu

SSHD_CONFIG=${SSHD_CONFIG:-/etc/ssh/sshd_config_opencode}

if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  printf '%s\n' "$SSH_PUBLIC_KEY" >"$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"

  if [ ! -f "$HOME/.ssh/ssh_host_ed25519_key" ]; then
    ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/ssh_host_ed25519_key"
  fi

  sshd -f "$SSHD_CONFIG"
fi

exec "$@"
```

Create `sshd_config`:

```text
Port 2222
ListenAddress 0.0.0.0
HostKey /home/opencode/.ssh/ssh_host_ed25519_key
PidFile /home/opencode/.ssh/sshd.pid
AuthorizedKeysFile /home/opencode/.ssh/authorized_keys
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
UsePAM no
AllowUsers opencode
Subsystem sftp internal-sftp
```

Make the script executable: `chmod +x docker-entrypoint.sh`.

Modify `Dockerfile` to declare `ARG INSTALL_SSH=true`, conditionally install `openssh-server openssh-client`, copy both files, and set:

```dockerfile
ARG INSTALL_SSH=true

RUN if [ "$INSTALL_SSH" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends openssh-server openssh-client && \
      rm -rf /var/lib/apt/lists/*; \
    fi

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY sshd_config /etc/ssh/sshd_config_opencode

ENTRYPOINT ["docker-entrypoint.sh"]
```

Keep `USER opencode` before the final `ENTRYPOINT`.

- [ ] **Step 4: Run entrypoint tests and validate Dockerfile syntax**

Run: `tests/entrypoint-smoke.sh`

Expected: PASS with no output.

Run: `docker build --check .`

Expected: exit 0 with no Dockerfile validation errors.

- [ ] **Step 5: Commit the SSH deliverable**

```bash
git add Dockerfile docker-entrypoint.sh sshd_config tests/entrypoint-smoke.sh
git commit -m "feat: add optional non-root SSH access"
```

---

### Task 2: Playwright and Camoufox CLI with upstream skills

**Files:**
- Modify: `Dockerfile`
- Create: `tests/browser-tools-smoke.sh`

**Interfaces:**
- Consumes: `INSTALL_PLAYWRIGHT` and `INSTALL_CAMOUFOX` Docker build arguments.
- Produces: `playwright-cli`, Chromium, `camoufox-cli`, Camoufox browser, and skills under `/home/opencode/.agents/skills/`.

- [ ] **Step 1: Add a failing browser-tool smoke test**

Create executable `tests/browser-tools-smoke.sh`:

```sh
#!/bin/sh
set -eu

IMAGE=${1:?usage: browser-tools-smoke.sh IMAGE}

docker run --rm --entrypoint sh "$IMAGE" -lc '
  playwright-cli --version
  camoufox-cli --version
  test -f "$HOME/.agents/skills/playwright-cli/SKILL.md"
  test -f "$HOME/.agents/skills/camoufox-cli/SKILL.md"
  playwright-cli open https://example.com >/tmp/playwright.out
  playwright-cli title | grep -F "Example Domain"
  playwright-cli close
  camoufox-cli open https://example.com >/tmp/camoufox.out
  camoufox-cli title | grep -F "Example Domain"
  camoufox-cli close
'
```

- [ ] **Step 2: Build the current image and prove the smoke test fails**

Run:

```bash
docker build -t worker-pod:browser-red \
  --build-arg INSTALL_SSH=false \
  --build-arg INSTALL_GH=false .
tests/browser-tools-smoke.sh worker-pod:browser-red
```

Expected: FAIL with `playwright-cli: not found`.

- [ ] **Step 3: Add conditional CLI, dependencies, browsers, and skills**

Add near the top of `Dockerfile`:

```dockerfile
ARG INSTALL_PLAYWRIGHT=true
ARG INSTALL_CAMOUFOX=true
ENV PLAYWRIGHT_BROWSERS_PATH=/home/opencode/.cache/ms-playwright
```

In the root installation phase, install the CLIs and system dependencies conditionally:

```dockerfile
RUN if [ "$INSTALL_PLAYWRIGHT" = "true" ]; then \
      npm install -g @playwright/cli@latest && \
      playwright-cli install-deps chromium; \
    fi && \
    if [ "$INSTALL_CAMOUFOX" = "true" ]; then \
      npm install -g camoufox-cli && \
      camoufox-cli install --with-deps && \
      mkdir -p /home/opencode/.cache && \
      cp -a /root/.cache/camoufox/. /home/opencode/.cache/camoufox/ && \
      chown -R opencode:opencode /home/opencode/.cache/camoufox; \
    fi && \
    rm -rf /var/lib/apt/lists/* /root/.npm
```

After creating/chowning `/home/opencode` and switching to `USER opencode`, install browser binaries and official upstream skills:

```dockerfile
RUN if [ "$INSTALL_PLAYWRIGHT" = "true" ]; then \
      playwright-cli install chromium && \
      playwright-cli install --skills; \
    fi && \
    if [ "$INSTALL_CAMOUFOX" = "true" ]; then \
      npx --yes skills add Bin-Huang/camoufox-cli --global --yes; \
    fi && \
    test "$INSTALL_PLAYWRIGHT" != "true" || test -f /home/opencode/.agents/skills/playwright-cli/SKILL.md && \
    test "$INSTALL_CAMOUFOX" != "true" || test -f /home/opencode/.agents/skills/camoufox-cli/SKILL.md
```

The `test -f` assertions deliberately fail the image build if an upstream
installer changes its destination. In that case, update the install command to
target `/home/opencode/.agents/skills` while retaining the complete generated
skill directory; do not copy only `SKILL.md`, because Playwright ships reference
files with its skill.

- [ ] **Step 4: Build and run browser smoke tests**

Run:

```bash
docker build -t worker-pod:browser-green \
  --build-arg INSTALL_SSH=false \
  --build-arg INSTALL_GH=false .
tests/browser-tools-smoke.sh worker-pod:browser-green
```

Expected: both version commands succeed, both skill files exist, and both browsers report `Example Domain` without downloading a browser at runtime.

- [ ] **Step 5: Commit the browser-tool deliverable**

```bash
git add Dockerfile tests/browser-tools-smoke.sh
git commit -m "feat: add optional Playwright and Camoufox tools"
```

---

### Task 3: GitHub CLI, Compose, and user documentation

**Files:**
- Modify: `Dockerfile`
- Modify: `docker-compose.yml`
- Modify: `.env.sample`
- Modify: `README.md`
- Create: `tests/tooling-config-smoke.sh`

**Interfaces:**
- Consumes: `INSTALL_GH` build argument, `GH_TOKEN` and `SSH_PUBLIC_KEY` runtime environment variables.
- Produces: official `gh` binary, compose SSH exposure, and documented build/runtime configuration.

- [ ] **Step 1: Add failing static configuration tests**

Create executable `tests/tooling-config-smoke.sh`:

```sh
#!/bin/sh
set -eu

grep -Fq 'ARG INSTALL_GH=true' Dockerfile
grep -Fq 'https://cli.github.com/packages/githubcli-archive-keyring.gpg' Dockerfile
grep -Fq '172.17.0.1:2222:2222' docker-compose.yml
grep -Fq 'SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}' docker-compose.yml
grep -Fq 'GH_TOKEN=${GH_TOKEN}' docker-compose.yml
grep -Fq 'SSH_PUBLIC_KEY=' .env.sample
grep -Fq 'GH_TOKEN=' .env.sample
grep -Fq 'INSTALL_PLAYWRIGHT' README.md
grep -Fq 'INSTALL_CAMOUFOX' README.md
grep -Fq 'INSTALL_GH' README.md
```

- [ ] **Step 2: Run the test and verify current config fails**

Run: `chmod +x tests/tooling-config-smoke.sh && tests/tooling-config-smoke.sh`

Expected: FAIL because `ARG INSTALL_GH=true` and the new compose/env/docs entries are absent.

- [ ] **Step 3: Install `gh` from GitHub's official apt repository**

Add `ARG INSTALL_GH=true` and this guarded root-phase block to `Dockerfile`:

```dockerfile
RUN if [ "$INSTALL_GH" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends ca-certificates curl && \
      mkdir -p -m 755 /etc/apt/keyrings && \
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
      chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
      apt-get update && \
      apt-get install -y --no-install-recommends gh && \
      rm -rf /var/lib/apt/lists/*; \
    fi
```

- [ ] **Step 4: Update Compose and sample environment**

Add to `docker-compose.yml` ports:

```yaml
      - "172.17.0.1:2222:2222"
```

Add to its environment list:

```yaml
      - SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY}
      - GH_TOKEN=${GH_TOKEN}
```

Append to `.env.sample`:

```dotenv
SSH_PUBLIC_KEY=
GH_TOKEN=
```

- [ ] **Step 5: Document build and runtime usage**

Add a `## Optional Tools` section to `README.md` containing this build example and a table describing all four default-true arguments:

```bash
docker build -t opencode-custom \
  --build-arg INSTALL_SSH=true \
  --build-arg INSTALL_PLAYWRIGHT=true \
  --build-arg INSTALL_CAMOUFOX=true \
  --build-arg INSTALL_GH=true .
```

Document:

```bash
ssh -p 2222 opencode@localhost
playwright-cli open https://example.com
camoufox-cli open https://example.com
GH_TOKEN=... gh auth status
```

State explicitly that SSH starts only when `SSH_PUBLIC_KEY` is non-empty, authentication is key-only, skills are installed in `~/.agents/skills`, browser binaries are preloaded, and GitHub tokens must only be provided at runtime.

- [ ] **Step 6: Run configuration checks and Compose validation**

Run:

```bash
tests/tooling-config-smoke.sh
SSH_PUBLIC_KEY='' GH_TOKEN='' TZ=UTC OPENCODE_SERVER_USERNAME='' OPENCODE_SERVER_PASSWORD='' docker compose config --quiet
```

Expected: both commands exit 0.

- [ ] **Step 7: Commit the GitHub CLI and docs deliverable**

```bash
git add Dockerfile docker-compose.yml .env.sample README.md tests/tooling-config-smoke.sh
git commit -m "feat: add optional GitHub CLI and tool configuration"
```

---

### Task 4: Full and lean Docker verification in CI

**Files:**
- Create: `tests/docker-smoke.sh`
- Modify: `.github/workflows/update-image.yml`

**Interfaces:**
- Consumes: complete Dockerfile, entrypoint, compose configuration, and all four build arguments.
- Produces: one command that proves full-image behavior and lean-image exclusions before publication.

- [ ] **Step 1: Add the end-to-end smoke script**

Create executable `tests/docker-smoke.sh`:

```sh
#!/bin/sh
set -eu

FULL_IMAGE=${FULL_IMAGE:-worker-pod:full-smoke}
LEAN_IMAGE=${LEAN_IMAGE:-worker-pod:lean-smoke}

docker build -t "$FULL_IMAGE" .
docker run --rm --entrypoint sh "$FULL_IMAGE" -lc '
  opencode --version
  ssh -V
  sshd -V 2>&1 | grep -F OpenSSH
  gh --version
  playwright-cli --version
  camoufox-cli --version
  test -f "$HOME/.agents/skills/playwright-cli/SKILL.md"
  test -f "$HOME/.agents/skills/camoufox-cli/SKILL.md"
'

docker build -t "$LEAN_IMAGE" \
  --build-arg INSTALL_SSH=false \
  --build-arg INSTALL_PLAYWRIGHT=false \
  --build-arg INSTALL_CAMOUFOX=false \
  --build-arg INSTALL_GH=false .
docker run --rm --entrypoint sh "$LEAN_IMAGE" -lc '
  opencode --version
  ! command -v sshd
  ! command -v playwright-cli
  ! command -v camoufox-cli
  ! command -v gh
'
```

- [ ] **Step 2: Run focused tests before the expensive builds**

Run:

```bash
tests/entrypoint-smoke.sh
tests/tooling-config-smoke.sh
docker build --check .
```

Expected: all commands exit 0.

- [ ] **Step 3: Run complete full/lean image verification**

Run: `tests/docker-smoke.sh`

Expected: full image exposes every binary and both skills; lean image exposes only OpenCode and none of the four optional tool binaries.

- [ ] **Step 4: Add pre-publish smoke checks to GitHub Actions**

In `.github/workflows/update-image.yml`, add `docker/setup-qemu-action@v3`
immediately before `docker/setup-buildx-action@v3`, then add this step before
the existing digest build/push step:

```yaml
      - name: Smoke test image tooling
        run: |
          docker buildx build \
            --platform "${{ matrix.platform }}" \
            --build-arg "OPENCODE_VERSION=${{ needs.check.outputs.version }}" \
            --load \
            -t "opencode-smoke:${{ steps.prepare.outputs.platform_pair }}" .
          docker run --rm --entrypoint sh \
            "opencode-smoke:${{ steps.prepare.outputs.platform_pair }}" -lc '
              opencode --version
              gh --version
              playwright-cli --version
              camoufox-cli --version
              test -f "$HOME/.agents/skills/playwright-cli/SKILL.md"
              test -f "$HOME/.agents/skills/camoufox-cli/SKILL.md"
            '
```

Keep the existing digest build/push step after this check. QEMU allows the
loaded `linux/arm64` smoke image to execute on the amd64 GitHub runner.

- [ ] **Step 5: Validate workflow syntax and inspect the final diff**

Run:

```bash
docker compose config --quiet
git diff --check
git status --short
```

Expected: Compose and diff checks pass; status lists only the intended workflow and smoke-test changes.

- [ ] **Step 6: Commit end-to-end verification**

```bash
git add tests/docker-smoke.sh .github/workflows/update-image.yml
git commit -m "test: verify optional tools in Docker builds"
```

---

## Final Verification

- [ ] Run all inexpensive checks:

```bash
tests/entrypoint-smoke.sh
tests/tooling-config-smoke.sh
docker build --check .
docker compose config --quiet
git diff --check
```

- [ ] Run browser and full/lean Docker checks:

```bash
tests/docker-smoke.sh
tests/browser-tools-smoke.sh worker-pod:full-smoke
```

- [ ] Manually verify SSH against the full image with a disposable key:

```bash
tmpdir=$(mktemp -d)
ssh-keygen -q -t ed25519 -N '' -f "$tmpdir/id"
docker run -d --rm --name worker-pod-ssh -p 127.0.0.1:2222:2222 \
  -e "SSH_PUBLIC_KEY=$(cat "$tmpdir/id.pub")" \
  worker-pod:full-smoke sleep 60
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -i "$tmpdir/id" -p 2222 opencode@127.0.0.1 true
docker rm -f worker-pod-ssh
rm -rf "$tmpdir"
```

Expected: SSH exits 0 without requesting a password.
