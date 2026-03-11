# Agent Runtime Notes

The repository Dockerfile intentionally keeps the runtime narrow:

- `opsro`
- `kubectl`
- CA certificates

This is a good starting point for a read-only agent container.

## Recommended Runtime Rules

When embedding Codex or Claude Code later:

- do not mount a write-capable kubeconfig
- mount only a dedicated read-only kubeconfig
- do not mount `~/.ssh`, cloud credentials, or a Docker socket
- prefer a read-only filesystem where practical
- keep the image tool surface small

## Suggested Pattern

Build an agent image on top of this runtime rather than putting cluster credentials into a developer workstation shell.
