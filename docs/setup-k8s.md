# Setup Kubernetes for opsro

This guide explains how to prepare a Kubernetes cluster for read-only `opsro` access.

## Goal

Create a dedicated read-only Kubernetes identity and mount its kubeconfig into the `opsro` container.

## Steps

### Recommended

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install-k8s-readonly.sh | sh
```

By default this creates the `opsro-reader` ServiceAccount in `opsro-system`, applies the read-only ClusterRole/Binding, and writes `./kubeconfig.opsro`.

Useful flags:

- `--context prod`
- `--namespace opsro-system`
- `--service-account opsro-reader`
- `--kubeconfig-out ./kubeconfig.opsro`
- `--print-kubeconfig`
- `--dry-run`

### Manual

1. Create the namespace if needed:

```bash
kubectl create namespace opsro-system
```

2. Apply the sample RBAC:

```bash
kubectl apply -f examples/rbac/readonly-clusterrole.yaml
```

3. Generate a read-only kubeconfig for the `opsro-reader` identity.
4. Mount that kubeconfig into the container, for example at `/config/kubeconfig`.
5. Set:

```bash
KUBECONFIG=/config/kubeconfig
```

## Verify

Examples:

```bash
kubectl --context prod auth can-i get pods --all-namespaces
kubectl --context prod auth can-i delete pods --all-namespaces
opsro k8s --context prod get pods -A
```

Expected result:

- read checks should pass
- write checks should fail

## Notes

- `opsro top ...` depends on cluster metrics support
- never mount an admin kubeconfig into the agent container
- keep the read-only kubeconfig separate from operator admin credentials
