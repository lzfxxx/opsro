# Agent Runtime Notes

The repository includes two runtime layers:

- `Dockerfile`: a narrow `opsro` runtime with `kubectl`
- `Dockerfile.agent`: an agent runtime for Codex or Claude Code on top of `opsro`

This keeps the plain CLI image simple while still supporting agent-specific containers.

## Recommended Runtime Rules

When embedding Codex or Claude Code later:

- do not mount a write-capable kubeconfig
- mount only a dedicated read-only kubeconfig
- do not mount `~/.ssh`, cloud credentials, or a Docker socket
- prefer a read-only filesystem where practical
- keep the image tool surface small

## Suggested Pattern

Build an agent image on top of this runtime rather than putting cluster credentials into a developer workstation shell.
