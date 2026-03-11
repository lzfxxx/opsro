#!/bin/sh
set -eu

if [ "$#" -eq 0 ] || [ "$1" = "/bin/sh" ] || [ "$1" = "sh" ]; then
  cat <<'EOF'
opsro agent runtime

Included tools:
- opsro
- agent CLI selected at build time

Hidden behind opsro:
- kubectl
- ssh

Examples:
  opsro k8s --context prod get pods -A
  opsro host status web-01
EOF
fi

exec "$@"
