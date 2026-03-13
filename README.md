# opsro

English | [简体中文](README.zh-CN.md)

`opsro` is a **read-only operations CLI for coding agents**.

It is designed for the setup where Codex / Claude Code runs inside an isolated container, then uses `opsro` to inspect Kubernetes and hosts through a narrow, controlled interface.

## What this project is for

Use `opsro` when you want an agent to:

- inspect Kubernetes with a read-only kubeconfig
- inspect hosts through a read-only SSH broker
- read logs and runtime state during incidents
- avoid direct shell access and broad credentials

## 1. Prepare the backend access

`opsro` is only the agent-facing CLI. The real security boundary stays in your backend.

### Easiest path

Use the bootstrap script to emit `kubeconfig.opsro`, `opsro.json`, and runnable agent scripts in one output directory:

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/bootstrap.sh | sh -s -- \
  --out-dir ./opsro-bootstrap \
  --host-name web-01 \
  --host-address 10.0.1.12
```

For the current MVP, K8s setup runs directly. Host setup can now run in three modes:

- emit a local helper script (default)
- install on the current machine with `--install-host-local`
- install on a remote machine with `--install-host-remote --remote-host ...`

### Kubernetes

Install read-only RBAC and generate a kubeconfig for that identity:

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install-k8s-readonly.sh | sh
```

You can still inspect the underlying example manifest at `examples/rbac/readonly-clusterrole.yaml`.

### Hosts

Install the read-only broker on the target host:

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install-host-broker.sh | sudo sh
```

Or let `bootstrap.sh` push the installer over SSH from the management node:

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/bootstrap.sh | sh -s -- \
  --out-dir ./opsro-bootstrap \
  --host-name web-01 \
  --host-address 10.0.1.12 \
  --install-host-remote \
  --remote-host 10.0.1.12 \
  --remote-ssh-user admin
```

Then configure host inventory from `examples/config.json`, or use the generated `opsro.json` in the bootstrap output directory.

See `docs/quickstart.md` for step-by-step setup and advanced flags.

## 2. Run the agent container

Pull images:

```bash
docker pull ghcr.io/lzfxxx/opsro-codex:latest
docker pull ghcr.io/lzfxxx/opsro-claude:latest
```

Both agent images expect:

- `KUBECONFIG=/config/kubeconfig`
- `OPSRO_CONFIG=/config/opsro.json`
- a read-only kubeconfig mounted at `/config/kubeconfig`
- an `opsro` inventory mounted at `/config/opsro.json`
- a writable workspace mounted at `/workspace`

### Codex

If `OPENAI_API_KEY` is present and Codex is not logged in yet, the `opsro-codex` entrypoint automatically runs:

```bash
printenv OPENAI_API_KEY | codex login --with-api-key
```

```bash
docker run --rm -it \
  -e OPENAI_API_KEY="$OPENAI_API_KEY" \
  -e OPENAI_BASE_URL="$OPENAI_BASE_URL" \
  -e KUBECONFIG=/config/kubeconfig \
  -e OPSRO_CONFIG=/config/opsro.json \
  -e CODEX_HOME=/root/.codex \
  -v $(pwd)/kubeconfig:/config/kubeconfig:ro \
  -v $(pwd)/opsro.json:/config/opsro.json:ro \
  -v $(pwd)/workspace:/workspace \
  -v opsro-codex-config:/root/.codex \
  ghcr.io/lzfxxx/opsro-codex:latest
```

If you do not pass API-key env vars, Codex falls back to its normal interactive login flow. Keep `/root/.codex` mounted if you want that login state to persist.

### Claude Code

```bash
docker run --rm -it \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e KUBECONFIG=/config/kubeconfig \
  -e OPSRO_CONFIG=/config/opsro.json \
  -v $(pwd)/kubeconfig:/config/kubeconfig:ro \
  -v $(pwd)/opsro.json:/config/opsro.json:ro \
  -v $(pwd)/workspace:/workspace \
  ghcr.io/lzfxxx/opsro-claude:latest
```

If you do not pass API-key env vars, use OAuth once and persist config:

```bash
docker run --rm -it \
  -e KUBECONFIG=/config/kubeconfig \
  -e OPSRO_CONFIG=/config/opsro.json \
  -v $(pwd)/kubeconfig:/config/kubeconfig:ro \
  -v $(pwd)/opsro.json:/config/opsro.json:ro \
  -v $(pwd)/workspace:/workspace \
  -v opsro-claude-config:/root/.config \
  ghcr.io/lzfxxx/opsro-claude:latest

# inside container
claude login
```

## 3. Use opsro inside the container

```bash
opsro k8s --context prod get pods -A
opsro k8s --context prod logs deployment/api -n prod --since=10m
opsro host status web-01
opsro host logs web-01 nginx --since=10m --tail=200
```

## How it works

```text
Codex / Claude Code / Human
            |
            v
          opsro
         /     \
        v       v
   kubectl       ssh
      |           |
      v           v
   K8s API     ForceCommand
    RBAC       readonly-broker
```

- Kubernetes safety comes from RBAC.
- Host safety comes from `ForceCommand` plus a read-only allowlist broker.
- The container image narrows the local tool surface by blocking direct `kubectl` / `ssh`, but it does not replace backend authorization.

## Roadmap

- remote host bootstrap from the management node instead of a generated local helper
- stronger runtime isolation and policy
- richer operational primitives for logs / metrics / traces
- approvals and audit trail for sensitive actions

## Optional

- `examples/docker-compose.agent.yml` if you want a reusable local template
- `scripts/install.sh` if you want to install the bare `opsro` CLI locally
- `docs/bootstrap.md`, `docs/containers.md`, `docs/quickstart.md`, `examples/` for more detail
