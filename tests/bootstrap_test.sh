#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BOOTSTRAP="$ROOT/scripts/bootstrap.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
FAKE_K8S="$TMP_DIR/fake-install-k8s.sh"
FAKE_HOST="$TMP_DIR/fake-install-host.sh"
OUT_DIR="$TMP_DIR/out"
HOST_LOG="$TMP_DIR/host.log"
SSH_LOG="$TMP_DIR/ssh.log"
SSH_STDIN="$TMP_DIR/ssh.stdin"

cat >"$FAKE_K8S" <<'EOF'
#!/bin/sh
set -eu
DRY_RUN=0
OUT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --kubeconfig-out)
      OUT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
if [ "$DRY_RUN" -eq 1 ]; then
  echo "fake-k8s dry-run"
  exit 0
fi
[ -n "$OUT" ] || exit 1
mkdir -p "$(dirname "$OUT")"
printf 'apiVersion: v1\nkind: Config\n' >"$OUT"
EOF
chmod +x "$FAKE_K8S"

cat >"$FAKE_HOST" <<EOF
#!/bin/sh
set -eu
printf '%s\n' "\$*" >"$HOST_LOG"
if [ "\${1:-}" = "--dry-run" ]; then
  echo "fake-host dry-run"
fi
EOF
chmod +x "$FAKE_HOST"

FAKE_SSH="$TMP_DIR/fake-ssh.sh"
cat >"$FAKE_SSH" <<EOF
#!/bin/sh
set -eu
printf '%s\n' "\$*" >"$SSH_LOG"
cat >"$SSH_STDIN"
EOF
chmod +x "$FAKE_SSH"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

plan_out=$(OPSRO_INSTALL_K8S_SCRIPT="$FAKE_K8S" OPSRO_INSTALL_HOST_SCRIPT="$FAKE_HOST" \
  "$BOOTSTRAP" --plan --out-dir "$OUT_DIR" --host-name web-01 --host-address 10.0.1.12 2>&1)
printf '%s\n' "$plan_out" | grep -q 'bootstrap: plan' || fail 'plan should announce itself'
printf '%s\n' "$plan_out" | grep -q 'host: web-01 (10.0.1.12:22 as opsro)' || fail 'plan should mention host'
[ ! -e "$OUT_DIR" ] || fail 'plan should not create output dir'

dry_out=$(OPSRO_INSTALL_K8S_SCRIPT="$FAKE_K8S" OPSRO_INSTALL_HOST_SCRIPT="$FAKE_HOST" \
  "$BOOTSTRAP" --dry-run --out-dir "$OUT_DIR" --host-name web-01 --host-address 10.0.1.12 2>&1)
printf '%s\n' "$dry_out" | grep -q 'fake-k8s dry-run' || fail 'dry-run should call k8s installer in dry-run mode'
printf '%s\n' "$dry_out" | grep -q 'would generate host installer helper at:' || fail 'dry-run should mention host helper generation'
printf '%s\n' "$dry_out" | grep -q '"web-01"' || fail 'dry-run should print opsro config'
[ ! -e "$OUT_DIR" ] || fail 'dry-run should not create output dir'

OPSRO_INSTALL_K8S_SCRIPT="$FAKE_K8S" OPSRO_INSTALL_HOST_SCRIPT="$FAKE_HOST" \
  "$BOOTSTRAP" --out-dir "$OUT_DIR" --provider both --host-name web-01 --host-address 10.0.1.12 --host-port 2222 >/dev/null 2>&1

[ -f "$OUT_DIR/kubeconfig.opsro" ] || fail 'bootstrap should write kubeconfig'
[ -f "$OUT_DIR/opsro.json" ] || fail 'bootstrap should write opsro.json'
[ -f "$OUT_DIR/run-codex.sh" ] || fail 'bootstrap should write codex run script'
[ -f "$OUT_DIR/run-claude.sh" ] || fail 'bootstrap should write claude run script'
[ -f "$OUT_DIR/host-install.sh" ] || fail 'bootstrap should write host helper script'
grep -q '10.0.1.12' "$OUT_DIR/opsro.json" || fail 'opsro.json should contain host address'
grep -q 'ghcr.io/lzfxxx/opsro-codex:latest' "$OUT_DIR/run-codex.sh" || fail 'codex run script should reference image'
grep -q 'ghcr.io/lzfxxx/opsro-claude:latest' "$OUT_DIR/run-claude.sh" || fail 'claude run script should reference image'

LOCAL_OUT="$TMP_DIR/out-local"
OPSRO_INSTALL_K8S_SCRIPT="$FAKE_K8S" OPSRO_INSTALL_HOST_SCRIPT="$FAKE_HOST" \
  "$BOOTSTRAP" --out-dir "$LOCAL_OUT" --provider codex --host-name web-02 --host-address 10.0.2.22 --install-host-local --skip-reload >/dev/null 2>&1
[ -f "$HOST_LOG" ] || fail 'local host install should invoke host installer'
grep -q -- '--user opsro --inventory-name web-02 --address 10.0.2.22 --port 22 --skip-reload' "$HOST_LOG" || fail 'local host installer args should be forwarded'
[ ! -f "$LOCAL_OUT/host-install.sh" ] || fail 'local host install should not emit helper script'

REMOTE_OUT="$TMP_DIR/out-remote"
OPSRO_INSTALL_K8S_SCRIPT="$FAKE_K8S" OPSRO_INSTALL_HOST_SCRIPT="$FAKE_HOST" OPSRO_BOOTSTRAP_SSH_BIN="$FAKE_SSH" \
  "$BOOTSTRAP" --out-dir "$REMOTE_OUT" --provider claude --host-name web-03 --host-address 10.0.3.33 --install-host-remote --remote-host admin.example --remote-ssh-user root --remote-ssh-port 2222 --remote-use-sudo --skip-reload >/dev/null 2>&1
[ -f "$SSH_LOG" ] || fail 'remote host install should invoke ssh'
grep -q -- '-p 2222' "$SSH_LOG" || fail 'remote host install should pass ssh port'
grep -q -- 'root@admin.example' "$SSH_LOG" || fail 'remote host install should target remote host'
grep -q -- 'sudo sh -s --' "$SSH_LOG" || fail 'remote host install should use sudo when requested'
grep -q -- '--inventory-name' "$SSH_LOG" || fail 'remote host install should forward installer args'
grep -q -- 'printf' "$SSH_STDIN" || fail 'remote host install should pipe installer script over ssh'
[ ! -f "$REMOTE_OUT/host-install.sh" ] || fail 'remote host install should not emit helper script'
[ -f "$REMOTE_OUT/run-claude.sh" ] || fail 'remote bootstrap should still emit requested provider script'

if OPSRO_INSTALL_K8S_SCRIPT="$FAKE_K8S" OPSRO_INSTALL_HOST_SCRIPT="$FAKE_HOST" \
  "$BOOTSTRAP" --out-dir "$TMP_DIR/bad" --host-address 10.0.1.12 >/dev/null 2>&1; then
  fail 'bootstrap should reject host-address without host-name'
fi

if OPSRO_INSTALL_K8S_SCRIPT="$FAKE_K8S" OPSRO_INSTALL_HOST_SCRIPT="$FAKE_HOST" \
  "$BOOTSTRAP" --out-dir "$TMP_DIR/bad-remote" --host-name web-04 --host-address 10.0.4.44 --install-host-remote >/dev/null 2>&1; then
  fail 'bootstrap should reject remote mode without remote host'
fi

printf 'bootstrap tests passed\n'
