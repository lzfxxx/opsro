#!/bin/sh
set -eu

install_if_missing() {
  src="$1"
  dst="$2"
  if [ ! -e "$dst" ]; then
    cp "$src" "$dst"
  fi
}

maybe_auto_login_codex() {
  if [ "${OPSRO_AGENT_BIN:-}" != "codex" ]; then
    return 0
  fi

  if [ -z "${OPENAI_API_KEY:-}" ]; then
    return 0
  fi

  if codex login status >/dev/null 2>&1; then
    return 0
  fi

  if printf '%s' "$OPENAI_API_KEY" | codex login --with-api-key >/dev/null 2>&1; then
    echo "Codex auto-login completed using OPENAI_API_KEY."
  else
    echo "Codex auto-login failed; run 'printenv OPENAI_API_KEY | codex login --with-api-key' inside the container to inspect the error." >&2
  fi
}

mkdir -p /workspace
mkdir -p "${CODEX_HOME:-/root/.codex}"
install_if_missing /opt/opsro/templates/AGENTS.md /workspace/AGENTS.md
install_if_missing /opt/opsro/templates/CLAUDE.md /workspace/CLAUDE.md
install_if_missing /opt/opsro/templates/ONBOARD.md /workspace/ONBOARD.md
install_if_missing /opt/opsro/templates/SETUP_K8S.md /workspace/SETUP_K8S.md
install_if_missing /opt/opsro/templates/SETUP_HOST.md /workspace/SETUP_HOST.md
install_if_missing /opt/opsro/templates/opsro.json.example /workspace/opsro.json.example

maybe_auto_login_codex

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
