#!/bin/sh
set -eu

BROKER_USER="opsro"
INSTALL_PATH="/usr/local/bin/readonly-broker"
SSHD_CONFIG_MAIN="/etc/ssh/sshd_config"
SSHD_CONFIG_FRAGMENT="/etc/ssh/sshd_config.d/opsro-readonly-broker.conf"
INVENTORY_NAME=""
ADDRESS=""
PORT="22"
REF="main"
SKIP_RELOAD=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Install the opsro read-only broker on a host.

Usage:
  install-host-broker.sh [options]

Options:
  --user NAME                 SSH user to force into the broker (default: opsro)
  --install-path PATH         broker install path (default: /usr/local/bin/readonly-broker)
  --sshd-config PATH          main sshd_config path (default: /etc/ssh/sshd_config)
  --sshd-fragment PATH        managed sshd config fragment path (default: /etc/ssh/sshd_config.d/opsro-readonly-broker.conf)
  --inventory-name NAME       host name to suggest in opsro.json (default: hostname)
  --address ADDR              host address to suggest in opsro.json (default: hostname -f or hostname)
  --port PORT                 SSH port to suggest in opsro.json (default: 22)
  --ref REF                   Git ref used when downloading the broker remotely (default: main)
  --skip-reload               do not reload sshd after writing config
  --dry-run                   print planned actions only
  -h, --help                  show this help
EOF
}

log() {
  printf '%s\n' "$*" >&2
}

fail() {
  log "install-host-broker: $*"
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing required command: $1"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --user)
      [ "$#" -ge 2 ] || fail "--user requires a value"
      BROKER_USER="$2"
      shift 2
      ;;
    --install-path)
      [ "$#" -ge 2 ] || fail "--install-path requires a value"
      INSTALL_PATH="$2"
      shift 2
      ;;
    --sshd-config)
      [ "$#" -ge 2 ] || fail "--sshd-config requires a value"
      SSHD_CONFIG_MAIN="$2"
      shift 2
      ;;
    --sshd-fragment)
      [ "$#" -ge 2 ] || fail "--sshd-fragment requires a value"
      SSHD_CONFIG_FRAGMENT="$2"
      shift 2
      ;;
    --inventory-name)
      [ "$#" -ge 2 ] || fail "--inventory-name requires a value"
      INVENTORY_NAME="$2"
      shift 2
      ;;
    --address)
      [ "$#" -ge 2 ] || fail "--address requires a value"
      ADDRESS="$2"
      shift 2
      ;;
    --port)
      [ "$#" -ge 2 ] || fail "--port requires a value"
      PORT="$2"
      shift 2
      ;;
    --ref)
      [ "$#" -ge 2 ] || fail "--ref requires a value"
      REF="$2"
      shift 2
      ;;
    --skip-reload)
      SKIP_RELOAD=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

need_cmd hostname
need_cmd chmod
need_cmd mkdir
need_cmd cp
need_cmd grep
need_cmd awk
need_cmd mktemp

if [ -z "$ADDRESS" ]; then
  ADDRESS=$(hostname -f 2>/dev/null || hostname)
fi

if [ -z "$INVENTORY_NAME" ]; then
  INVENTORY_NAME=$(hostname -s 2>/dev/null || hostname)
fi

render_sshd_block() {
  cat <<EOF
Match User ${BROKER_USER}
    ForceCommand ${INSTALL_PATH}
    PermitTTY no
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
    GatewayPorts no
    PermitUserEnvironment no
EOF
}

render_inventory_snippet() {
  cat <<EOF
"${INVENTORY_NAME}": {
  "address": "${ADDRESS}",
  "user": "${BROKER_USER}",
  "port": ${PORT}
}
EOF
}

NOLOGIN_SHELL="/usr/sbin/nologin"
if [ ! -x "$NOLOGIN_SHELL" ]; then
  if [ -x /sbin/nologin ]; then
    NOLOGIN_SHELL=/sbin/nologin
  else
    NOLOGIN_SHELL=/bin/false
  fi
fi

fetch_broker() {
  script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
  local_source="$script_dir/../brokers/host-readonly/readonly-broker.sh"
  if [ -f "$local_source" ]; then
    cp "$local_source" "$INSTALL_PATH"
    return 0
  fi

  need_cmd curl
  curl -fsSL "https://raw.githubusercontent.com/lzfxxx/opsro/${REF}/brokers/host-readonly/readonly-broker.sh" -o "$INSTALL_PATH"
}

ensure_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "please run as root"
  fi
}

ensure_user() {
  if id -u "$BROKER_USER" >/dev/null 2>&1; then
    return 0
  fi

  if command -v useradd >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "/var/lib/${BROKER_USER}" --shell "$NOLOGIN_SHELL" "$BROKER_USER"
    return 0
  fi

  if command -v adduser >/dev/null 2>&1; then
    adduser --system --home "/var/lib/${BROKER_USER}" --shell "$NOLOGIN_SHELL" "$BROKER_USER"
    return 0
  fi

  fail "could not create user; neither useradd nor adduser is available"
}

replace_managed_block() {
  file="$1"
  block="$2"
  tmp=$(mktemp)
  awk '
    BEGIN { skip = 0 }
    /^# BEGIN opsro-readonly-broker$/ { skip = 1; next }
    /^# END opsro-readonly-broker$/ { skip = 0; next }
    skip == 0 { print }
  ' "$file" >"$tmp"
  {
    cat "$tmp"
    printf '\n# BEGIN opsro-readonly-broker\n'
    printf '%s\n' "$block"
    printf '# END opsro-readonly-broker\n'
  } >"$file"
  rm -f "$tmp"
}

write_sshd_config() {
  block=$(render_sshd_block)
  fragment_dir=$(dirname "$SSHD_CONFIG_FRAGMENT")

  if [ -f "$SSHD_CONFIG_MAIN" ] && grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CONFIG_MAIN"; then
    mkdir -p "$fragment_dir"
    printf '%s\n' "$block" >"$SSHD_CONFIG_FRAGMENT"
    return 0
  fi

  [ -f "$SSHD_CONFIG_MAIN" ] || fail "sshd config not found: $SSHD_CONFIG_MAIN"
  replace_managed_block "$SSHD_CONFIG_MAIN" "$block"
}

validate_sshd_config() {
  if command -v sshd >/dev/null 2>&1; then
    sshd -t -f "$SSHD_CONFIG_MAIN"
    return 0
  fi

  if [ -x /usr/sbin/sshd ]; then
    /usr/sbin/sshd -t -f "$SSHD_CONFIG_MAIN"
    return 0
  fi

  log "warning: sshd binary not found; skipping config validation"
}

reload_sshd() {
  if [ "$SKIP_RELOAD" -eq 1 ]; then
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || fail "failed to reload sshd via systemctl"
    return 0
  fi

  if command -v service >/dev/null 2>&1; then
    service sshd reload 2>/dev/null || service ssh reload 2>/dev/null || fail "failed to reload sshd via service"
    return 0
  fi

  log "warning: could not reload sshd automatically; please reload it manually"
}

if [ "$DRY_RUN" -eq 1 ]; then
  log "install-host-broker: dry run"
  log "would install broker to: $INSTALL_PATH"
  log "would manage ssh user:   $BROKER_USER"
  log "would use nologin shell: $NOLOGIN_SHELL"
  log "would write ssh config:  $SSHD_CONFIG_FRAGMENT or managed block in $SSHD_CONFIG_MAIN"
  log "suggested opsro.json snippet:"
  render_inventory_snippet
  log "sshd snippet:"
  render_sshd_block
  exit 0
fi

ensure_root
mkdir -p "$(dirname "$INSTALL_PATH")"
fetch_broker
chmod 0755 "$INSTALL_PATH"
ensure_user
write_sshd_config
validate_sshd_config
reload_sshd

log "installed broker: $INSTALL_PATH"
log "managed SSH user: $BROKER_USER"
log "suggested opsro.json snippet:"
render_inventory_snippet
