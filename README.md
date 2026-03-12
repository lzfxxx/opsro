# opsro

English | [简体中文](README.zh-CN.md)

`opsro` is a **read-only operations CLI** for AI agents and humans.

It gives Codex / Claude Code a narrow, predictable surface for production inspection instead of handing them a general-purpose shell, `kubectl`, or `ssh`.

## What this project is for

Use `opsro` when you want an agent to:

- inspect Kubernetes safely with a read-only kubeconfig
- inspect hosts through a read-only SSH broker
- read logs and runtime state during incidents
- avoid broad credentials and direct shell access

## Install CLI

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install.sh | sh
```

Pin a version:

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install.sh | sh -s -- --version v0.3.2
```

The installer downloads the matching release binary for your OS/arch and installs `opsro` into `/usr/local/bin`, `$HOME/.local/bin`, or `./bin`.

If you only want the agent containers, you can skip local CLI install and go straight to Docker.

## Quick Start

Pull images:

```bash
docker pull ghcr.io/lzfxxx/opsro-codex:latest
docker pull ghcr.io/lzfxxx/opsro-claude:latest
```

Both images expect:

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

Examples:

- `examples/docker-compose.agent.yml`
- `examples/.env.codex.example`
- `examples/.env.claude.example`

## Kubernetes RBAC

Apply the sample read-only RBAC and generate a kubeconfig for that identity:

- `examples/rbac/readonly-clusterrole.yaml`

Then you can run:

```bash
./bin/opsro k8s --context prod get pods -A
./bin/opsro k8s --context prod logs deployment/api -n prod --since=10m
```

## Host Read-Only Broker

On the target host:

1. Install `brokers/host-readonly/readonly-broker.sh` as `/usr/local/bin/readonly-broker`
2. Create a low-privilege SSH user such as `opsro`
3. Force that user into the broker with SSH `ForceCommand`
4. Configure inventory from `examples/config.json`

Then you can run:

```bash
./bin/opsro host status web-01
./bin/opsro host logs web-01 nginx --since=10m --tail=200
./bin/opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
```

See `docs/quickstart.md` for the exact `sshd_config` example.

## Mechanism

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

- stronger runtime isolation and policy
- richer operational primitives for logs / metrics / traces
- approvals and audit trail for sensitive actions
- better multi-cluster and multi-host ergonomics

More detail:

- `docs/quickstart.md`
- `docs/containers.md`
- `examples/`
