#!/bin/sh
set -eu

SSHD_CONFIG=${SSHD_CONFIG:-/etc/ssh/sshd_config_opencode}
SSHD=${SSHD:-/usr/sbin/sshd}

# ── SSH (optional) ───────────────────────────────────────────────────
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
  if ! command -v ssh-keygen >/dev/null 2>&1 || ! command -v "$SSHD" >/dev/null 2>&1; then
    echo "ERROR: SSH_PUBLIC_KEY is set but SSH binaries are not installed." \
         "Rebuild the image with INSTALL_SSH=true." >&2
    exit 1
  fi

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  printf '%s\n' "$SSH_PUBLIC_KEY" >"$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"

  if [ ! -f "$HOME/.ssh/ssh_host_ed25519_key" ]; then
    ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/ssh_host_ed25519_key"
  fi

  "$SSHD" -f "$SSHD_CONFIG"
fi

# ── opencode serve (optional, default: true) ─────────────────────────
if [ "${OPENCODE_SERVE:-true}" = "true" ]; then
  echo "Starting opencode serve on port 4096 ..."
  opencode serve --hostname 0.0.0.0 --port 4096 &
fi

# ── opencode-mcp HTTP transport (optional) ───────────────────────────
if [ -n "${OPENCODE_MCP_HTTP_TOKEN:-}" ]; then
  echo "Starting opencode-mcp (HTTP on port ${OPENCODE_MCP_HTTP_PORT:-3000}) ..."
  OPENCODE_MCP_TRANSPORT=http \
  OPENCODE_BASE_URL=http://127.0.0.1:4096 \
  OPENCODE_MCP_HTTP_HOST=0.0.0.0 \
  OPENCODE_MCP_HTTP_PORT=${OPENCODE_MCP_HTTP_PORT:-3000} \
  OPENCODE_MCP_HTTP_TOKEN="${OPENCODE_MCP_HTTP_TOKEN}" \
  OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}" \
  OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD:-}" \
  OPENCODE_AUTO_SERVE=false \
  opencode-mcp &
fi

exec "$@"
