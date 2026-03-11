# Architecture

V1 keeps the architecture intentionally small.

## Design

```text
Codex / Claude Code
        |
        v
      opsro
        |
        v
     kubectl
        |
        v
 Kubernetes API Server
```

The real security boundary for Kubernetes is RBAC, not the CLI.

`opsro` narrows the command surface for agents by exposing only a small set of read-only verbs:

- `get`
- `describe`
- `logs`
- `events`
- `top`

## Why This Works

- Kubernetes already has a strong authorization model
- Agents need a stable CLI surface more than they need a new control plane
- A narrow wrapper is easier to audit than a general shell

## Future Extensions

Host inspection uses a separate read-only broker and does not reuse the Kubernetes trust model.

That shape looks like this:

```text
Codex / Claude Code
        |
        v
      opsro
      /   \
     v     v
 kubectl   host-readonly-broker
             |
             v
      SSH ForceCommand / local runner
```
