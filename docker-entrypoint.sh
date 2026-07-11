#!/bin/sh
set -eu

SSHD_CONFIG=${SSHD_CONFIG:-/etc/ssh/sshd_config_opencode}
SSHD=${SSHD:-/usr/sbin/sshd}

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

exec "$@"
