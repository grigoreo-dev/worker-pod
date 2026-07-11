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
