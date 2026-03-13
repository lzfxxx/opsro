#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ENTRYPOINT_SRC="$ROOT/docker/agent-entrypoint.sh"
DENY_SRC="$ROOT/docker/deny-direct.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
TEMPLATES_DIR="$TMP_DIR/templates"
WORKSPACE_DIR="$TMP_DIR/workspace"
FAKE_BIN="$TMP_DIR/bin"
CODEX_HOME_DIR="$TMP_DIR/codex-home"
LOGIN_LOG="$TMP_DIR/codex.log"
mkdir -p "$TEMPLATES_DIR" "$WORKSPACE_DIR" "$FAKE_BIN"

for name in AGENTS.md CLAUDE.md ONBOARD.md SETUP_K8S.md SETUP_HOST.md opsro.json.example; do
  printf '%s\n' "$name" >"$TEMPLATES_DIR/$name"
done

ENTRYPOINT_TEST="$TMP_DIR/agent-entrypoint.test.sh"
sed \
  -e "s|/opt/opsro/templates|$TEMPLATES_DIR|g" \
  -e "s|/workspace|$WORKSPACE_DIR|g" \
  "$ENTRYPOINT_SRC" >"$ENTRYPOINT_TEST"
chmod +x "$ENTRYPOINT_TEST"

cat >"$FAKE_BIN/codex" <<EOF
#!/bin/sh
set -eu
printf '%s\n' "\$*" >>"$LOGIN_LOG"
if [ "\${1:-}" = "login" ] && [ "\${2:-}" = "status" ]; then
  exit 1
fi
if [ "\${1:-}" = "login" ] && [ "\${2:-}" = "--with-api-key" ]; then
  cat >/dev/null
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_BIN/codex"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

out=$(PATH="$FAKE_BIN:$PATH" OPSRO_AGENT_BIN=codex OPENAI_API_KEY=sk-test CODEX_HOME="$CODEX_HOME_DIR" "$ENTRYPOINT_TEST" /bin/echo ready 2>&1)
printf '%s\n' "$out" | grep -q 'Codex auto-login completed' || fail 'entrypoint should auto-login codex when key is present'
[ -d "$CODEX_HOME_DIR" ] || fail 'entrypoint should create CODEX_HOME'
[ -f "$WORKSPACE_DIR/AGENTS.md" ] || fail 'entrypoint should seed AGENTS.md'
[ -f "$WORKSPACE_DIR/opsro.json.example" ] || fail 'entrypoint should seed opsro example'
grep -q 'login --with-api-key' "$LOGIN_LOG" || fail 'entrypoint should invoke codex login --with-api-key'

: >"$LOGIN_LOG"
out=$(PATH="$FAKE_BIN:$PATH" OPSRO_AGENT_BIN=claude CODEX_HOME="$CODEX_HOME_DIR" "$ENTRYPOINT_TEST" /bin/echo ready 2>&1)
printf '%s\n' "$out" | grep -q 'ready' || fail 'entrypoint should exec requested command'
[ ! -s "$LOGIN_LOG" ] || fail 'entrypoint should not call codex for non-codex agent'

if sh "$DENY_SRC" 2>"$TMP_DIR/deny.err"; then
  fail 'deny-direct should exit non-zero'
fi
grep -q 'is intentionally hidden in this image' "$TMP_DIR/deny.err" || fail 'deny-direct should explain why access is blocked'

printf 'container script tests passed\n'
