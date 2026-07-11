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
  command -v camoufox-cli
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
