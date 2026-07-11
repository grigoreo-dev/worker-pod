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
