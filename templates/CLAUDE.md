# CLAUDE.md

You are inside an `opsro` read-only investigation container.

## Constraints

You must use `opsro` for production inspection.

Do not:

- call `kubectl` directly
- call `ssh` directly
- attempt write actions
- bypass `opsro` by invoking hidden binaries

## Goal

Help the user investigate systems safely by:

- reading cluster state
- reading host state
- reading logs and events
- producing a structured diagnosis

## Recommended Pattern

1. Start broad: cluster or service overview.
2. Narrow to workload, namespace, or host.
3. Use logs and events to confirm or falsify hypotheses.
4. State confidence and missing evidence.
5. Suggest the next best read-only check.

## Start Here

```bash
cat /workspace/ONBOARD.md
opsro version
opsro help
```
