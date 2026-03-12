# SETUP_K8S.md

This guide explains how to prepare a Kubernetes cluster for read-only `opsro` access.

## Goal

Create a dedicated read-only Kubernetes identity that can be mounted into the `opsro` container through `KUBECONFIG`.

## 1. Create the namespace if needed

```bash
kubectl create namespace opsro-system
```

## 2. Apply the sample read-only RBAC

```bash
kubectl apply -f examples/rbac/readonly-clusterrole.yaml
```

This creates:

- `ServiceAccount`: `opsro-reader`
- `ClusterRole`: `opsro-readonly`
- `ClusterRoleBinding`: `opsro-readonly`

## 3. Generate a read-only kubeconfig

Use the service account token or your platform's preferred identity flow to generate a kubeconfig that authenticates as the read-only identity.

The resulting kubeconfig should:

- point to the target cluster
- contain only a read-only identity
- define a clear context name such as `prod` or `staging`

Mount this file into the container, for example:

```text
/config/kubeconfig
```

And set:

```bash
KUBECONFIG=/config/kubeconfig
```

## 4. Verify permissions

From an admin shell, verify that the identity can read but cannot write.

Examples:

```bash
kubectl --context prod auth can-i get pods --all-namespaces
kubectl --context prod auth can-i list deployments --all-namespaces
kubectl --context prod auth can-i get events --all-namespaces
kubectl --context prod auth can-i delete pods --all-namespaces
kubectl --context prod auth can-i patch deployments --all-namespaces
```

Expected result:

- read queries should return `yes`
- write queries should return `no`

## 5. Verify from inside opsro

```bash
opsro version
opsro k8s --context prod get pods -A
opsro k8s --context prod events -n prod
```

## Notes

- `opsro top ...` requires metrics support in the cluster
- keep this kubeconfig separate from your admin kubeconfig
- do not mount a write-capable kubeconfig into the agent container
