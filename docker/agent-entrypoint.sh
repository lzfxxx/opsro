#!/bin/sh
set -eu

install_if_missing() {
  src="$1"
  dst="$2"
  if [ ! -e "$dst" ]; then
    cp "$src" "$dst"
  fi
}

mkdir -p /workspace
install_if_missing /opt/opsro/templates/AGENTS.md /workspace/AGENTS.md
install_if_missing /opt/opsro/templates/CLAUDE.md /workspace/CLAUDE.md
install_if_missing /opt/opsro/templates/ONBOARD.md /workspace/ONBOARD.md
install_if_missing /opt/opsro/templates/SETUP_K8S.md /workspace/SETUP_K8S.md
install_if_missing /opt/opsro/templates/SETUP_HOST.md /workspace/SETUP_HOST.md
install_if_missing /opt/opsro/templates/opsro.json.example /workspace/opsro.json.example

if [ "$#" -eq 0 ] || [ "$1" = "/bin/sh" ] || [ "$1" = "sh" ]; then
  cat <<'EOF'
opsro agent runtime

The following files have been seeded into /workspace if they were missing:
- AGENTS.md
- CLAUDE.md
- ONBOARD.md
- SETUP_K8S.md
- SETUP_HOST.md
- opsro.json.example

Start here:
  cat /workspace/ONBOARD.md
  opsro version
  opsro help
EOF
fi

exec "$@"
