#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
K8S_INSTALLER="$ROOT/scripts/install-k8s-readonly.sh"
HOST_INSTALLER="$ROOT/scripts/install-host-broker.sh"

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

k8s_out=$(
  "$K8S_INSTALLER" --dry-run \
    --context prod \
    --namespace demo-ns \
    --service-account demo-reader \
    --cluster-role demo-role \
    --binding demo-binding \
    --kubeconfig-out /tmp/demo-kubeconfig 2>&1
)

printf '%s\n' "$k8s_out" | grep -q 'kind: ServiceAccount' || fail 'k8s dry-run should render ServiceAccount'
printf '%s\n' "$k8s_out" | grep -q 'name: demo-reader' || fail 'k8s dry-run should include service account name'
printf '%s\n' "$k8s_out" | grep -q 'would write generated kubeconfig to: /tmp/demo-kubeconfig' || fail 'k8s dry-run should mention kubeconfig path'

host_out=$(
  "$HOST_INSTALLER" --dry-run \
    --user demo-user \
    --inventory-name web-01 \
    --address 10.0.1.12 \
    --port 2222 \
    --install-path /tmp/readonly-broker \
    --sshd-config /tmp/sshd_config \
    --sshd-fragment /tmp/sshd_config.d/opsro-readonly-broker.conf 2>&1
)

printf '%s\n' "$host_out" | grep -q 'would install broker to: /tmp/readonly-broker' || fail 'host dry-run should mention broker path'
printf '%s\n' "$host_out" | grep -q 'Match User demo-user' || fail 'host dry-run should render sshd block'
printf '%s\n' "$host_out" | grep -q '"address": "10.0.1.12"' || fail 'host dry-run should render inventory snippet'

printf 'installer tests passed\n'
