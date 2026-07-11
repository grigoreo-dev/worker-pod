FROM node:24.15.0-bookworm

ARG OPENCODE_VERSION=latest
ARG INSTALL_SSH=true
ARG INSTALL_PLAYWRIGHT=true
ARG INSTALL_CAMOUFOX=true
ARG INSTALL_GH=true

# Playwright browser binaries will be stored here (accessible by opencode user)
ENV PLAYWRIGHT_BROWSERS_PATH=/home/opencode/.cache/ms-playwright

# set working directory
WORKDIR /app

# check architecture
RUN uname -m

# install opencode globally
RUN npm i -g "opencode-ai@${OPENCODE_VERSION}" && \
  installed_version_raw="$(opencode --version)" && \
  installed_version="${installed_version_raw#v}" && \
  echo "Installed opencode version: ${installed_version}" && \
  if [ "${OPENCODE_VERSION}" != "latest" ] && [ "${installed_version}" != "${OPENCODE_VERSION}" ]; then \
    echo "Expected opencode version ${OPENCODE_VERSION}, got ${installed_version}" >&2; \
    exit 1; \
  fi

RUN if [ "$INSTALL_SSH" = "true" ]; then \
      apt-get update && \
      apt-get install -y --no-install-recommends openssh-server openssh-client && \
      rm -rf /var/lib/apt/lists/*; \
    fi

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

# Install browser CLIs and system dependencies (root phase).
# playwright-cli install-browser --with-deps: installs OS-level libraries for Chromium
# AND downloads the Chromium binary to $PLAYWRIGHT_BROWSERS_PATH.
# camoufox-cli install --with-deps invokes sudo internally; we install sudo first so it
# works when running as root during the Docker build.
# The Camoufox browser lands in /root/.cache/camoufox (userCacheDir for root).
RUN apt-get update && \
    apt-get install -y --no-install-recommends sudo && \
    if [ "$INSTALL_PLAYWRIGHT" = "true" ]; then \
      npm install -g @playwright/cli@latest && \
      playwright-cli install-browser --with-deps chromium; \
    fi && \
    if [ "$INSTALL_CAMOUFOX" = "true" ]; then \
      npm install -g camoufox-cli && \
      camoufox-cli install --with-deps && \
      ARCH="$(uname -m)" && \
      if [ "$ARCH" = "x86_64" ]; then \
        CAMOUFOX_URL="https://github.com/daijro/camoufox/releases/download/v150.0.2-beta.25/camoufox-150.0.2-alpha.26-lin.x86_64.zip" && \
        CAMOUFOX_VERSION_JSON='{"version":"150.0.2","release":"alpha.26"}'; \
      else \
        CAMOUFOX_URL="https://github.com/daijro/camoufox/releases/download/v150.0.2-beta.25/camoufox-150.0.2-alpha.25-lin.arm64.zip" && \
        CAMOUFOX_VERSION_JSON='{"version":"150.0.2","release":"alpha.25"}'; \
      fi && \
      apt-get install -y --no-install-recommends unzip && \
      curl -fsSL "$CAMOUFOX_URL" -o /tmp/camoufox.zip && \
      mkdir -p /root/.cache/camoufox && \
      unzip -o /tmp/camoufox.zip -d /root/.cache/camoufox/ && \
      echo "$CAMOUFOX_VERSION_JSON" > /root/.cache/camoufox/version.json && \
      chmod -R 755 /root/.cache/camoufox/ && \
      rm -f /tmp/camoufox.zip; \
    fi && \
    rm -rf /var/lib/apt/lists/* /root/.npm

# non-root user (recommended)
RUN adduser --disabled-password opencode

# create necessary directories and set permissions.
# Move Camoufox browser from root's cache into opencode home so the non-root
# user can read it at runtime without re-downloading.
RUN mkdir -p /home/opencode/.local/share/opencode/ && \
  mkdir -p /home/opencode/.local/state/opencode && \
  mkdir -p /home/opencode/.config/opencode/ && \
  mkdir -p /home/opencode/.agents/skills && \
  if [ "$INSTALL_CAMOUFOX" = "true" ] && [ -d /root/.cache/camoufox ]; then \
    mkdir -p /home/opencode/.cache && \
    cp -a /root/.cache/camoufox/. /home/opencode/.cache/camoufox/; \
  fi && \
  chown -R opencode:opencode /home/opencode

COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY sshd_config /etc/ssh/sshd_config_opencode

# switch to non-root user and set home as working directory so that
# playwright-cli install --skills writes skill files under ~/.claude/skills/
USER opencode
WORKDIR /home/opencode

# Install browser binaries and upstream skills (user phase).
# playwright-cli install --skills: Chromium already at $PLAYWRIGHT_BROWSERS_PATH from root
# phase, so this skips the browser download and just installs the playwright skill to
# .claude/skills/playwright-cli/ relative to WORKDIR (/home/opencode).
# We then copy the full skill directory to ~/.agents/skills/ where opencode looks for skills.
# npx skills add installs the camoufox-cli skill directly to ~/.agents/skills/camoufox-cli/.
RUN if [ "$INSTALL_PLAYWRIGHT" = "true" ]; then \
      playwright-cli install --skills && \
      mkdir -p /home/opencode/.agents/skills && \
      cp -a /home/opencode/.claude/skills/playwright-cli/. /home/opencode/.agents/skills/playwright-cli/; \
    fi && \
    if [ "$INSTALL_CAMOUFOX" = "true" ]; then \
      npx --yes skills add Bin-Huang/camoufox-cli --global --yes; \
    fi && \
    { test "$INSTALL_PLAYWRIGHT" != "true" || test -f /home/opencode/.agents/skills/playwright-cli/SKILL.md; } && \
    { test "$INSTALL_CAMOUFOX" != "true" || test -f /home/opencode/.agents/skills/camoufox-cli/SKILL.md; }

ENTRYPOINT ["docker-entrypoint.sh"]

# docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/pilinux/opencode:0.0.1 --output type=docker .
