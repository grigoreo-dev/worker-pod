#!/bin/sh
set -eu

IMAGE=${1:?usage: browser-tools-smoke.sh IMAGE}

docker run --rm --network host --entrypoint sh "$IMAGE" -lc '
  playwright-cli --version
  command -v camoufox-cli
  test -f "$HOME/.agents/skills/playwright-cli/SKILL.md"
  test -f "$HOME/.agents/skills/camoufox-cli/SKILL.md"
  test -f "$HOME/.cache/camoufox/camoufox-bin"
  test -f "$HOME/.cache/camoufox/libxul.so"
  test -f "$HOME/.cache/camoufox/version.json"
'
