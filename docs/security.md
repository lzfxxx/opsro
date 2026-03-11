# Security Model

## Kubernetes

For V1, Kubernetes safety comes from:

1. a dedicated read-only kubeconfig
2. Kubernetes RBAC
3. `opsro` only exposing read-only verbs

`opsro` is a client-side narrowing layer. RBAC is the real enforcement boundary.

## What V1 Does Not Try To Solve

- host command authorization
- approval workflows
- per-action write controls
- cloud mutation guardrails

Those belong in later phases.

## Agent Runtime Guidance

When used with Codex or Claude Code:

- run the agent in a container or sandboxed environment
- mount only the read-only kubeconfig
- do not mount `~/.ssh`, `~/.kube/config`, or cloud credentials
- tell the agent to use `opsro`, not raw `kubectl`

## Host Access Direction

For host inspection, the recommended V2 direction is:

- a dedicated `opsro` subcommand
- a host read-only broker
- SSH `ForceCommand` or a local runner on the host
- an allowlist of read-only host commands
