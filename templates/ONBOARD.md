# ONBOARD.md

You are inside an `opsro` read-only operations environment.

This environment is designed for production investigation, not production mutation.

## What You Can Do

- inspect Kubernetes clusters with `opsro k8s ...`
- inspect hosts with `opsro host ...`
- read logs, events, workload state, and runtime state
- summarize findings, likely causes, and next steps

## What You Cannot Do

- do not call `kubectl` directly
- do not call `ssh` directly
- do not search for hidden binaries under `/opt/opsro/bin`
- do not assume write access exists
- do not attempt to mutate clusters or hosts

## First Checks

Start here:

```bash
opsro version
opsro help
```

If Kubernetes is expected:

```bash
echo "$KUBECONFIG"
opsro k8s --context <context> get pods -A
```

If host inspection is expected:

```bash
echo "$OPSRO_CONFIG"
cat "$OPSRO_CONFIG"
opsro host status <host>
```

## Common Commands

### Kubernetes

```bash
opsro k8s --context prod get pods -A
opsro k8s --context prod describe deployment api -n prod
opsro k8s --context prod logs deployment/api -n prod --since=10m
opsro k8s --context prod events -n prod
opsro k8s --context prod top pods -n prod
```

### Hosts

```bash
opsro host status web-01
opsro host logs web-01 nginx --since=10m --tail=200
opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
```

## Recommended Investigation Flow

1. Check cluster-wide health.
2. Narrow down to the affected namespace or workload.
3. Inspect logs and events.
4. If needed, inspect related hosts.
5. Summarize:
   - what was observed
   - likely cause
   - confidence level
   - suggested next step

## Common Problems

### `opsro k8s ...` fails

Check:

- `KUBECONFIG` is mounted
- the context name is correct
- the kubeconfig is valid and read-only
- RBAC grants read access

### `opsro host ...` fails

Check:

- `OPSRO_CONFIG` exists
- the host alias exists in config
- SSH reaches the host
- the host `opsro` user uses `ForceCommand`
- `readonly-broker` is installed on the host

## More Setup Help

See:

- `/workspace/SETUP_K8S.md`
- `/workspace/SETUP_HOST.md`
