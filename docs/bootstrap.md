# Bootstrap opsro

`scripts/bootstrap.sh` is the lightweight orchestrator for the current setup flow.

It keeps the logic simple:

- calls `install-k8s-readonly.sh`
- emits `opsro.json`
- emits runnable `run-codex.sh` / `run-claude.sh`
- optionally emits `host-install.sh` or runs the host installer locally

## Recommended

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/bootstrap.sh | sh -s -- \
  --out-dir ./opsro-bootstrap \
  --host-name web-01 \
  --host-address 10.0.1.12
```

This creates an output directory such as:

- `opsro-bootstrap/kubeconfig.opsro`
- `opsro-bootstrap/opsro.json`
- `opsro-bootstrap/run-codex.sh`
- `opsro-bootstrap/run-claude.sh`
- `opsro-bootstrap/host-install.sh` (when host info is provided and host install is not local)

## Useful flags

- `--context prod`
- `--provider codex|claude|both`
- `--host-name web-01`
- `--host-address 10.0.1.12`
- `--host-port 22`
- `--host-user opsro`
- `--install-host-local`
- `--skip-reload`
- `--plan`
- `--dry-run`

## Scope

Current MVP behavior:

- K8s installer runs directly.
- Host inventory is generated when host metadata is provided.
- Host setup defaults to a generated helper script unless `--install-host-local` is used.

Future work: remote host bootstrap from the management node.
