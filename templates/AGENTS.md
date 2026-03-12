# AGENTS.md

You are operating inside an `opsro` read-only production investigation environment.

## Core Rule

Use `opsro` as the operations interface.

Do not:

- call `kubectl` directly
- call `ssh` directly
- search for hidden binaries under `/opt/opsro/bin`
- assume write access exists
- attempt cluster or host mutations

## What You Can Do

- inspect Kubernetes clusters with `opsro k8s ...`
- inspect hosts with `opsro host ...`
- read logs, events, workload state, and runtime state
- summarize findings, likely causes, and next steps

## Investigation Flow

1. Check cluster-wide state first.
2. Narrow down to the affected namespace, workload, or node.
3. Inspect logs and events.
4. If needed, inspect related hosts.
5. Summarize:
   - what you observed
   - likely cause
   - confidence level
   - recommended next query or next action

## Output Style

Prefer:

- concise summary first
- evidence second
- uncertainty stated clearly
- proposed next steps last

## First Commands

```bash
cat /workspace/ONBOARD.md
opsro version
opsro help
```
