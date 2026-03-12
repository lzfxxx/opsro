#!/bin/sh
set -eu

NAMESPACE="opsro-system"
SERVICE_ACCOUNT="opsro-reader"
CLUSTER_ROLE="opsro-readonly"
CLUSTER_ROLE_BINDING="opsro-readonly"
KUBECONFIG_OUT="./kubeconfig.opsro"
CONTEXT=""
PRINT_KUBECONFIG=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Install read-only Kubernetes access for opsro.

Usage:
  install-k8s-readonly.sh [options]

Options:
  --context NAME              kubectl context to use
  --namespace NAME            namespace for the ServiceAccount (default: opsro-system)
  --service-account NAME      ServiceAccount name (default: opsro-reader)
  --cluster-role NAME         ClusterRole name (default: opsro-readonly)
  --binding NAME              ClusterRoleBinding name (default: opsro-readonly)
  --kubeconfig-out PATH       write generated kubeconfig to PATH (default: ./kubeconfig.opsro)
  --print-kubeconfig          print kubeconfig to stdout instead of writing a file
  --dry-run                   print the manifest and planned actions only
  -h, --help                  show this help
EOF
}

log() {
  printf '%s\n' "$*" >&2
}

fail() {
  log "install-k8s-readonly: $*"
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing required command: $1"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
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
    --cluster-role)
      [ "$#" -ge 2 ] || fail "--cluster-role requires a value"
      CLUSTER_ROLE="$2"
      shift 2
      ;;
    --binding)
      [ "$#" -ge 2 ] || fail "--binding requires a value"
      CLUSTER_ROLE_BINDING="$2"
      shift 2
      ;;
    --kubeconfig-out)
      [ "$#" -ge 2 ] || fail "--kubeconfig-out requires a value"
      KUBECONFIG_OUT="$2"
      shift 2
      ;;
    --print-kubeconfig)
      PRINT_KUBECONFIG=1
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

run_kubectl() {
  if [ -n "$CONTEXT" ]; then
    kubectl --context "$CONTEXT" "$@"
  else
    kubectl "$@"
  fi
}

render_manifest() {
  cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SERVICE_ACCOUNT}
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${CLUSTER_ROLE}
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "endpoints", "events", "namespaces", "nodes", "configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["metrics.k8s.io"]
    resources: ["pods", "nodes"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${CLUSTER_ROLE_BINDING}
subjects:
  - kind: ServiceAccount
    name: ${SERVICE_ACCOUNT}
    namespace: ${NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${CLUSTER_ROLE}
EOF
}

if [ "$DRY_RUN" -eq 1 ]; then
  log "install-k8s-readonly: dry run"
  if [ -n "$CONTEXT" ]; then
    log "context: $CONTEXT"
  fi
  render_manifest
  if [ "$PRINT_KUBECONFIG" -eq 1 ]; then
    log "would print generated kubeconfig to stdout"
  else
    log "would write generated kubeconfig to: $KUBECONFIG_OUT"
  fi
  exit 0
fi

need_cmd kubectl

log "applying read-only RBAC for opsro"
render_manifest | run_kubectl apply -f -

cluster_name=$(run_kubectl config view --minify --raw -o jsonpath='{.clusters[0].name}')
server=$(run_kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')
ca_data=$(run_kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

[ -n "$cluster_name" ] || fail "could not resolve cluster name from current kubeconfig"
[ -n "$server" ] || fail "could not resolve cluster server from current kubeconfig"
[ -n "$ca_data" ] || fail "could not resolve certificate-authority-data from current kubeconfig"

token=$(run_kubectl -n "$NAMESPACE" create token "$SERVICE_ACCOUNT") || fail "failed to create token; this script expects 'kubectl create token' support"
[ -n "$token" ] || fail "received empty service account token"

generated_context="opsro-${cluster_name}"
render_kubeconfig() {
  cat <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ${cluster_name}
  cluster:
    certificate-authority-data: ${ca_data}
    server: ${server}
contexts:
- name: ${generated_context}
  context:
    cluster: ${cluster_name}
    namespace: ${NAMESPACE}
    user: ${SERVICE_ACCOUNT}
current-context: ${generated_context}
users:
- name: ${SERVICE_ACCOUNT}
  user:
    token: ${token}
EOF
}

verify_kubeconfig_path="$KUBECONFIG_OUT"
if [ "$PRINT_KUBECONFIG" -eq 1 ]; then
  verify_kubeconfig_path=$(mktemp)
  render_kubeconfig | tee "$verify_kubeconfig_path"
else
  mkdir -p "$(dirname "$KUBECONFIG_OUT")"
  render_kubeconfig >"$KUBECONFIG_OUT"
  log "wrote kubeconfig: $KUBECONFIG_OUT"
fi

can_get=$(KUBECONFIG="$verify_kubeconfig_path" kubectl auth can-i get pods --all-namespaces 2>/dev/null || true)
can_delete=$(KUBECONFIG="$verify_kubeconfig_path" kubectl auth can-i delete pods --all-namespaces 2>/dev/null || true)

log "verification: get pods => ${can_get:-unknown}"
log "verification: delete pods => ${can_delete:-unknown}"

if [ "$PRINT_KUBECONFIG" -eq 1 ]; then
  rm -f "$verify_kubeconfig_path"
fi
