#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
INSTALLER="$ROOT/scripts/install.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
FAKE_BIN="$TMP_DIR/fake-bin"
INSTALL_DIR="$TMP_DIR/install-bin"
mkdir -p "$FAKE_BIN" "$INSTALL_DIR" "$TMP_DIR/home"

make_fake() {
  name="$1"
  shift
  {
    printf '#!/bin/sh\n'
    printf '%s\n' "$*"
  } >"$FAKE_BIN/$name"
  chmod +x "$FAKE_BIN/$name"
}

make_fake uname 'case "$1" in -s) echo Darwin ;; -m) echo x86_64 ;; *) echo Darwin ;; esac'
make_fake curl '
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[ -n "$output" ]
printf "fake archive" >"$output"
'
cat >"$FAKE_BIN/tar" <<'EOF'
#!/bin/sh
set -eu
dest=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -C)
      dest="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[ -n "$dest" ]
cat >"$dest/opsro" <<'EOS'
#!/bin/sh
if [ "${1:-}" = "version" ]; then
  echo fake-version
else
  echo fake-opsro
fi
EOS
chmod +x "$dest/opsro"
EOF
chmod +x "$FAKE_BIN/tar"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

out=$(PATH="$FAKE_BIN:$PATH" HOME="$TMP_DIR/home" "$INSTALLER" --dry-run --version v9.9.9 --install-dir "$INSTALL_DIR" 2>&1)
printf '%s\n' "$out" | grep -q 'version: v9.9.9' || fail 'dry-run should show version'
printf '%s\n' "$out" | grep -q 'opsro_Darwin_x86_64.tar.gz' || fail 'dry-run should resolve asset name'
[ ! -f "$INSTALL_DIR/opsro" ] || fail 'dry-run should not install binary'

out=$(PATH="$FAKE_BIN:$PATH" HOME="$TMP_DIR/home" "$INSTALLER" --version v9.9.9 --install-dir "$INSTALL_DIR" 2>&1)
[ -x "$INSTALL_DIR/opsro" ] || fail 'installer should write executable binary'
printf '%s\n' "$out" | grep -q 'installed: ' || fail 'install should report installed path'
printf '%s\n' "$out" | grep -q 'fake-version' || fail 'installed binary should run version command'

if PATH="$FAKE_BIN:$PATH" HOME="$TMP_DIR/home" "$INSTALLER" --bogus >/dev/null 2>&1; then
  fail 'installer should reject unknown arguments'
fi

printf 'install tests passed\n'
