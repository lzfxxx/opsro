#!/bin/sh
set -eu

OUT_DIR="./opsro-bootstrap"
CONTEXT=""
NAMESPACE="opsro-system"
SERVICE_ACCOUNT="opsro-reader"
PROVIDER="both"
HOST_NAME=""
HOST_ADDRESS=""
HOST_PORT="22"
HOST_USER="opsro"
PLAN=0
DRY_RUN=0
INSTALL_HOST_LOCAL=0
INSTALL_HOST_REMOTE=0
REMOTE_HOST=""
REMOTE_SSH_USER="root"
REMOTE_SSH_PORT="22"
REMOTE_USE_SUDO=0
SKIP_RELOAD=0
REF="${OPSRO_REPO_REF:-main}"
TMP_DIR=""
SSH_BIN="${OPSRO_BOOTSTRAP_SSH_BIN:-ssh}"

usage() {
  cat <<'EOF'
Bootstrap opsro backend access and emit runnable agent artifacts.

Usage:
  bootstrap.sh [options]

Options:
  --out-dir DIR              output directory (default: ./opsro-bootstrap)
  --context NAME             kubectl context for K8s installer
  --namespace NAME           namespace for the ServiceAccount (default: opsro-system)
  --service-account NAME     ServiceAccount name (default: opsro-reader)
  --provider NAME            codex, claude, or both (default: both)
  --host-name NAME           host name to place into opsro.json
  --host-address ADDR        host address to place into opsro.json
  --host-port PORT           host SSH port (default: 22)
  --host-user NAME           host SSH user for opsro inventory (default: opsro)
  --install-host-local       run host installer on the current machine
  --install-host-remote      run host installer on a remote machine via SSH
  --remote-host ADDR         SSH target used with --install-host-remote
  --remote-ssh-user NAME     SSH user for remote install (default: root)
  --remote-ssh-port PORT     SSH port for remote install (default: 22)
  --remote-use-sudo          prefix the remote installer with sudo
  --skip-reload              pass --skip-reload to the host installer
  --plan                     print planned actions only
  --dry-run                  run installers in dry-run mode and print generated artifacts
  --ref REF                  Git ref used when downloading helper scripts remotely (default: main)
  -h, --help                 show this help

Environment overrides for testing:
  OPSRO_INSTALL_K8S_SCRIPT
  OPSRO_INSTALL_HOST_SCRIPT
EOF
}

log() {
  printf '%s\n' "$*" >&2
}

fail() {
  log "bootstrap: $*"
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing required command: $1"
  fi
}

cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --out-dir)
      [ "$#" -ge 2 ] || fail "--out-dir requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --context)
      [ "$#" -ge 2 ] || fail "--context requires a value"
      CONTEXT="$2"
      shift 2
      ;;
    --namespace)
      [ "$#" -ge 2 ] || fail "--namespace requires a value"
      NAMESPACE="$2"
      shift 2
      ;;
    --service-account)
      [ "$#" -ge 2 ] || fail "--service-account requires a value"
      SERVICE_ACCOUNT="$2"
      shift 2
      ;;
    --provider)
      [ "$#" -ge 2 ] || fail "--provider requires a value"
      PROVIDER="$2"
      shift 2
      ;;
    --host-name)
      [ "$#" -ge 2 ] || fail "--host-name requires a value"
      HOST_NAME="$2"
      shift 2
      ;;
    --host-address)
      [ "$#" -ge 2 ] || fail "--host-address requires a value"
      HOST_ADDRESS="$2"
      shift 2
      ;;
    --host-port)
      [ "$#" -ge 2 ] || fail "--host-port requires a value"
      HOST_PORT="$2"
      shift 2
      ;;
    --host-user)
      [ "$#" -ge 2 ] || fail "--host-user requires a value"
      HOST_USER="$2"
      shift 2
      ;;
    --install-host-local)
      INSTALL_HOST_LOCAL=1
      shift
      ;;
    --install-host-remote)
      INSTALL_HOST_REMOTE=1
      shift
      ;;
    --remote-host)
      [ "$#" -ge 2 ] || fail "--remote-host requires a value"
      REMOTE_HOST="$2"
      shift 2
      ;;
    --remote-ssh-user)
      [ "$#" -ge 2 ] || fail "--remote-ssh-user requires a value"
      REMOTE_SSH_USER="$2"
      shift 2
      ;;
    --remote-ssh-port)
      [ "$#" -ge 2 ] || fail "--remote-ssh-port requires a value"
      REMOTE_SSH_PORT="$2"
      shift 2
      ;;
    --remote-use-sudo)
      REMOTE_USE_SUDO=1
      shift
      ;;
    --skip-reload)
      SKIP_RELOAD=1
      shift
      ;;
    --plan)
      PLAN=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --ref)
      [ "$#" -ge 2 ] || fail "--ref requires a value"
      REF="$2"
      shift 2
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

case "$PROVIDER" in
  codex|claude|both) ;;
  *) fail "--provider must be one of: codex, claude, both" ;;
esac

if [ -n "$HOST_NAME" ] && [ -z "$HOST_ADDRESS" ]; then
  fail "--host-address is required when --host-name is set"
fi
if [ -n "$HOST_ADDRESS" ] && [ -z "$HOST_NAME" ]; then
  fail "--host-name is required when --host-address is set"
fi
if [ "$INSTALL_HOST_LOCAL" -eq 1 ] && [ -z "$HOST_NAME" ]; then
  fail "--host-name and --host-address are required with --install-host-local"
fi
if [ "$INSTALL_HOST_REMOTE" -eq 1 ] && [ -z "$HOST_NAME" ]; then
  fail "--host-name and --host-address are required with --install-host-remote"
fi
if [ "$INSTALL_HOST_LOCAL" -eq 1 ] && [ "$INSTALL_HOST_REMOTE" -eq 1 ]; then
  fail "--install-host-local and --install-host-remote are mutually exclusive"
fi
if [ "$INSTALL_HOST_REMOTE" -eq 1 ] && [ -z "$REMOTE_HOST" ]; then
  fail "--remote-host is required with --install-host-remote"
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" 2>/dev/null && pwd || pwd)

resolve_helper() {
  env_override="$1"
  local_name="$2"
  remote_name="$3"

  eval "override_value=\${$env_override:-}"
  if [ -n "$override_value" ]; then
    printf '%s\n' "$override_value"
    return 0
  fi

  local_path="$SCRIPT_DIR/$local_name"
  if [ -f "$local_path" ]; then
    printf '%s\n' "$local_path"
    return 0
  fi

  need_cmd curl
  if [ -z "$TMP_DIR" ]; then
    TMP_DIR=$(mktemp -d)
  fi
  fetched="$TMP_DIR/$(basename "$remote_name")"
  curl -fsSL "https://raw.githubusercontent.com/lzfxxx/opsro/${REF}/scripts/${remote_name}" -o "$fetched"
  chmod +x "$fetched"
  printf '%s\n' "$fetched"
}

K8S_INSTALLER=$(resolve_helper OPSRO_INSTALL_K8S_SCRIPT install-k8s-readonly.sh install-k8s-readonly.sh)
HOST_INSTALLER=$(resolve_helper OPSRO_INSTALL_HOST_SCRIPT install-host-broker.sh install-host-broker.sh)

KUBECONFIG_PATH="$OUT_DIR/kubeconfig.opsro"
OPSRO_CONFIG_PATH="$OUT_DIR/opsro.json"
RUN_CODEX_PATH="$OUT_DIR/run-codex.sh"
RUN_CLAUDE_PATH="$OUT_DIR/run-claude.sh"
HOST_INSTALL_PATH="$OUT_DIR/host-install.sh"

render_opsro_config() {
  if [ -n "$HOST_NAME" ]; then
    cat <<EOF
{
  "hosts": {
    "${HOST_NAME}": {
      "address": "${HOST_ADDRESS}",
      "user": "${HOST_USER}",
      "port": ${HOST_PORT}
    }
  }
}
EOF
  else
    cat <<'EOF'
{
  "hosts": {}
}
EOF
  fi
}

write_run_script() {
  provider_name="$1"
  output_path="$2"

  if [ "$provider_name" = "codex" ]; then
    cat >"$output_path" <<'EOF'
#!/bin/sh
set -eu
BASE_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
exec docker run --rm -it \
  -e OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
  -e OPENAI_BASE_URL="${OPENAI_BASE_URL:-}" \
  -e KUBECONFIG=/config/kubeconfig \
  -e OPSRO_CONFIG=/config/opsro.json \
  -e CODEX_HOME=/root/.codex \
  -v "$BASE_DIR/kubeconfig.opsro:/config/kubeconfig:ro" \
  -v "$BASE_DIR/opsro.json:/config/opsro.json:ro" \
  -v "$BASE_DIR/workspace:/workspace" \
  -v opsro-codex-config:/root/.codex \
  ghcr.io/lzfxxx/opsro-codex:latest
EOF
  else
    cat >"$output_path" <<'EOF'
#!/bin/sh
set -eu
BASE_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
exec docker run --rm -it \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  -e KUBECONFIG=/config/kubeconfig \
  -e OPSRO_CONFIG=/config/opsro.json \
  -v "$BASE_DIR/kubeconfig.opsro:/config/kubeconfig:ro" \
  -v "$BASE_DIR/opsro.json:/config/opsro.json:ro" \
  -v "$BASE_DIR/workspace:/workspace" \
  ghcr.io/lzfxxx/opsro-claude:latest
EOF
  fi
  chmod +x "$output_path"
}

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\''/g")"
}

render_host_install_script() {
  sudo_prefix=""
  if [ "$REMOTE_USE_SUDO" -eq 1 ]; then
    sudo_prefix="sudo "
  fi
  cat <<EOF
#!/bin/sh
set -eu
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/${REF}/scripts/install-host-broker.sh | ${sudo_prefix}sh -s -- \
  --user ${HOST_USER} \
  --inventory-name ${HOST_NAME} \
  --address ${HOST_ADDRESS} \
  --port ${HOST_PORT}$( [ "$SKIP_RELOAD" -eq 1 ] && printf ' \\
  --skip-reload' )
EOF
}

build_host_installer_args() {
  set -- --user "$HOST_USER" --inventory-name "$HOST_NAME" --address "$HOST_ADDRESS" --port "$HOST_PORT"
  if [ "$SKIP_RELOAD" -eq 1 ]; then
    set -- "$@" --skip-reload
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    set -- --dry-run "$@"
  fi
  printf '%s\n' "$@"
}

run_remote_host_bootstrap() {
  need_cmd "$SSH_BIN"
  remote_target="${REMOTE_SSH_USER}@${REMOTE_HOST}"
  remote_cmd="sh -s --"
  if [ "$REMOTE_USE_SUDO" -eq 1 ]; then
    remote_cmd="sudo $remote_cmd"
  fi
  while IFS= read -r arg; do
    remote_cmd="$remote_cmd $(shell_quote "$arg")"
  done <<EOF
$(build_host_installer_args)
EOF

  if [ "$DRY_RUN" -eq 1 ]; then
    log "would install host remotely via SSH: ${remote_target}:${REMOTE_SSH_PORT}"
    log "remote command: $remote_cmd"
    return 0
  fi

  "$SSH_BIN" -p "$REMOTE_SSH_PORT" "$remote_target" "$remote_cmd" <"$HOST_INSTALLER"
}

run_k8s_bootstrap() {
  cmd="$K8S_INSTALLER"
  set -- --namespace "$NAMESPACE" --service-account "$SERVICE_ACCOUNT" --kubeconfig-out "$KUBECONFIG_PATH"
  if [ -n "$CONTEXT" ]; then
    set -- --context "$CONTEXT" "$@"
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    set -- --dry-run "$@"
  fi
  "$cmd" "$@"
}

run_host_bootstrap() {
  if [ -z "$HOST_NAME" ]; then
    return 0
  fi

  if [ "$INSTALL_HOST_LOCAL" -eq 1 ]; then
    set --
    while IFS= read -r arg; do
      set -- "$@" "$arg"
    done <<EOF
$(build_host_installer_args)
EOF
    "$HOST_INSTALLER" "$@"
    return 0
  fi

  if [ "$INSTALL_HOST_REMOTE" -eq 1 ]; then
    run_remote_host_bootstrap
    return 0
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "would generate host installer helper at: $HOST_INSTALL_PATH"
    render_host_install_script
  fi
}

if [ "$PLAN" -eq 1 ]; then
  log "bootstrap: plan"
  log "output directory: $OUT_DIR"
  log "provider: $PROVIDER"
  log "kubeconfig output: $KUBECONFIG_PATH"
  log "opsro config output: $OPSRO_CONFIG_PATH"
  if [ -n "$HOST_NAME" ]; then
    if [ "$INSTALL_HOST_LOCAL" -eq 1 ]; then
      log "host install mode: local"
    elif [ "$INSTALL_HOST_REMOTE" -eq 1 ]; then
      log "host install mode: remote (${REMOTE_SSH_USER}@${REMOTE_HOST}:${REMOTE_SSH_PORT})"
    else
      log "host install mode: emit helper script"
    fi
    log "host: $HOST_NAME ($HOST_ADDRESS:$HOST_PORT as $HOST_USER)"
  else
    log "host: skipped"
  fi
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  log "bootstrap: dry run"
  run_k8s_bootstrap
  log "would write opsro config to: $OPSRO_CONFIG_PATH"
  render_opsro_config
  run_host_bootstrap
  log "would write helper scripts:"
  case "$PROVIDER" in
    codex) log "  - $RUN_CODEX_PATH" ;;
    claude) log "  - $RUN_CLAUDE_PATH" ;;
    both)
      log "  - $RUN_CODEX_PATH"
      log "  - $RUN_CLAUDE_PATH"
      ;;
  esac
  exit 0
fi

mkdir -p "$OUT_DIR/workspace"
run_k8s_bootstrap
render_opsro_config >"$OPSRO_CONFIG_PATH"

if [ -n "$HOST_NAME" ] && [ "$INSTALL_HOST_LOCAL" -eq 0 ] && [ "$INSTALL_HOST_REMOTE" -eq 0 ]; then
  render_host_install_script >"$HOST_INSTALL_PATH"
  chmod +x "$HOST_INSTALL_PATH"
fi
if [ -n "$HOST_NAME" ] && { [ "$INSTALL_HOST_LOCAL" -eq 1 ] || [ "$INSTALL_HOST_REMOTE" -eq 1 ]; }; then
  run_host_bootstrap
fi

case "$PROVIDER" in
  codex)
    write_run_script codex "$RUN_CODEX_PATH"
    ;;
  claude)
    write_run_script claude "$RUN_CLAUDE_PATH"
    ;;
  both)
    write_run_script codex "$RUN_CODEX_PATH"
    write_run_script claude "$RUN_CLAUDE_PATH"
    ;;
esac

log "bootstrap complete"
log "  kubeconfig:  $KUBECONFIG_PATH"
log "  opsro.json:  $OPSRO_CONFIG_PATH"
if [ -f "$HOST_INSTALL_PATH" ]; then
  log "  host helper: $HOST_INSTALL_PATH"
fi
case "$PROVIDER" in
  codex) log "  run:        $RUN_CODEX_PATH" ;;
  claude) log "  run:        $RUN_CLAUDE_PATH" ;;
  both)
    log "  run:        $RUN_CODEX_PATH"
    log "  run:        $RUN_CLAUDE_PATH"
    ;;
esac
