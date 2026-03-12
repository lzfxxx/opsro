#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BROKER="$ROOT/brokers/host-readonly/readonly-broker.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

make_fake() {
  name="$1"
  shift
  {
    printf '#!/bin/sh\n'
    printf '%s\n' "$*"
  } >"$FAKE_BIN/$name"
  chmod +x "$FAKE_BIN/$name"
}

make_fake hostname 'echo test-host'
make_fake uptime 'echo up 1 day'
make_fake free 'echo free-output'
make_fake df 'echo df-output'
make_fake ss 'echo ss-output'
make_fake systemctl 'echo systemctl:$*'
make_fake journalctl 'echo journalctl:$*'
make_fake uname 'echo uname:$*'
make_fake cat 'echo cat:$*'

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

expect_ok() {
  name="$1"
  cmd="$2"
  out=$(PATH="$FAKE_BIN:$PATH" SSH_ORIGINAL_COMMAND="$cmd" sh "$BROKER" 2>&1) || fail "expected success for $name: $out"
  printf '%s\n' "$out"
}

expect_fail() {
  name="$1"
  cmd="$2"
  if out=$(PATH="$FAKE_BIN:$PATH" SSH_ORIGINAL_COMMAND="$cmd" sh "$BROKER" 2>&1); then
    fail "expected failure for $name: $out"
  fi
  printf '%s\n' "$out"
}

status_out=$(expect_ok "status" "opsro-broker status")
printf '%s\n' "$status_out" | grep -q 'test-host' || fail 'status should include hostname'
printf '%s\n' "$status_out" | grep -q 'ss-output' || fail 'status should include ss output'

logs_out=$(expect_ok "logs" "opsro-broker logs nginx --since=15m --tail=50")
printf '%s\n' "$logs_out" | grep -q 'journalctl:-u nginx --since=15m -n 50 --no-pager' || fail 'logs should call journalctl with sanitized args'

run_out=$(expect_ok "run uname" "opsro-broker run uname -a")
printf '%s\n' "$run_out" | grep -q 'uname:-a' || fail 'run should allow uname'

cat_out=$(expect_ok "run cat" "opsro-broker run cat /etc/hosts")
printf '%s\n' "$cat_out" | grep -q 'cat:/etc/hosts' || fail 'run should allow cat on safe paths'

expect_fail "missing prefix" "uname -a" | grep -q 'expected opsro-broker prefix' || fail 'missing prefix should be rejected'
expect_fail "bad service token" "opsro-broker logs nginx;id" | grep -q 'unsafe service name' || fail 'unsafe service name should be rejected'
expect_fail "disallowed command" "opsro-broker run bash -lc id" | grep -q 'command not allowed' || fail 'bash should be rejected'
expect_fail "unsafe cat path" "opsro-broker run cat /root/secret" | grep -q 'cat path not allowed' || fail 'unsafe cat path should be rejected'

printf 'broker tests passed\n'
