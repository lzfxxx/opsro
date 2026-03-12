#!/bin/sh
set -eu

REPO_OWNER="lzfxxx"
REPO_NAME="opsro"
VERSION="latest"
INSTALL_DIR=""
DRY_RUN=0

usage() {
  cat <<'EOF'
Install opsro from GitHub Releases.

Usage:
  install.sh [--version vX.Y.Z] [--install-dir DIR] [--dry-run]

Examples:
  curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install.sh | sh -s -- --version v0.3.2
EOF
}

log() {
  printf '%s\n' "$*" >&2
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "missing required command: $1"
    exit 1
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      if [ "$#" -lt 2 ]; then
        log "--version requires a value"
        exit 1
      fi
      VERSION="$2"
      shift 2
      ;;
    --install-dir)
      if [ "$#" -lt 2 ]; then
        log "--install-dir requires a value"
        exit 1
      fi
      INSTALL_DIR="$2"
      shift 2
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
      log "unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

need_cmd uname
need_cmd curl
need_cmd tar
need_cmd mktemp

OS=$(uname -s)
ARCH=$(uname -m)

case "$OS" in
  Linux) ASSET_OS="Linux" ;;
  Darwin) ASSET_OS="Darwin" ;;
  *)
    log "unsupported operating system: $OS"
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64|amd64) ASSET_ARCH="x86_64" ;;
  arm64|aarch64) ASSET_ARCH="arm64" ;;
  *)
    log "unsupported architecture: $ARCH"
    exit 1
    ;;
esac

if [ -z "$INSTALL_DIR" ]; then
  if [ -w /usr/local/bin ]; then
    INSTALL_DIR=/usr/local/bin
  elif [ -d "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
    INSTALL_DIR=$HOME/.local/bin
  else
    INSTALL_DIR=$PWD/bin
  fi
fi

ASSET_NAME="opsro_${ASSET_OS}_${ASSET_ARCH}.tar.gz"
BASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases"
if [ "$VERSION" = "latest" ]; then
  DOWNLOAD_URL="${BASE_URL}/latest/download/${ASSET_NAME}"
else
  DOWNLOAD_URL="${BASE_URL}/download/${VERSION}/${ASSET_NAME}"
fi

log "installing opsro"
log "  version: $VERSION"
log "  asset:   $ASSET_NAME"
log "  target:  $INSTALL_DIR/opsro"
log "  source:  $DOWNLOAD_URL"

if [ "$DRY_RUN" -eq 1 ]; then
  exit 0
fi

TMP_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

ARCHIVE_PATH="$TMP_DIR/$ASSET_NAME"
curl -fsSL "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"
mkdir -p "$INSTALL_DIR"
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"
install_path="$INSTALL_DIR/opsro"
cp "$TMP_DIR/opsro" "$install_path"
chmod +x "$install_path"

log "installed: $install_path"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    log "note: $INSTALL_DIR is not currently on PATH"
    ;;
esac

"$install_path" version
