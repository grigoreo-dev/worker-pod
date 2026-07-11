#!/bin/sh
set -eu

IMAGE=${1:?usage: browser-tools-smoke.sh IMAGE}

docker run --rm --network host --entrypoint sh "$IMAGE" -lc '
  playwright-cli --version
  camoufox-cli --help 2>&1 | head -1
  test -f "$HOME/.agents/skills/playwright-cli/SKILL.md"
  test -f "$HOME/.agents/skills/camoufox-cli/SKILL.md"
'
