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
