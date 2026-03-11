# opsro

`opsro` is a read-only operations CLI for AI agents and humans.

V1 is intentionally narrow:

- read-only Kubernetes inspection
- production-safe defaults via Kubernetes RBAC
- read-only host inspection through SSH `ForceCommand`
- easy integration with Codex and Claude Code

It is not a full agent platform. It is the narrow waist between an agent and production systems.

## Goals

- Default to read-only investigation
- Reuse existing Kubernetes RBAC instead of inventing a new permission model
- Keep the agent interface simple: one CLI, predictable output
- Leave write actions and approvals for V2

## V1 Scope

- `opsro k8s get`
- `opsro k8s describe`
- `opsro k8s logs`
- `opsro k8s events`
- `opsro k8s top`
- `opsro host status`
- `opsro host logs`
- `opsro host run`
- sample read-only RBAC manifest
- sample host read-only broker

## Non-Goals

- direct write operations
- approval workflows
- MCP server
- host mutation commands
- cloud API mutation

## Why not just use kubectl?

You can, and `opsro` does shell out to `kubectl` in V1.

The point of `opsro` is to give agents a smaller, safer command surface:

- a fixed read-only command set
- stable usage patterns for prompts/skills
- a path to add host/log integrations later without changing the agent contract

## Quick Start

### 1. Build

```bash
go build -o bin/opsro ./cmd/opsro
```

### 2. Prepare a read-only kubeconfig

Use the sample RBAC in `examples/rbac/readonly-clusterrole.yaml` and generate a kubeconfig that maps to that read-only identity.

### 3. Run read-only queries

```bash
./bin/opsro k8s --context prod get pods -A
./bin/opsro k8s --context prod describe deployment api -n prod
./bin/opsro k8s --context prod logs deployment/api -n prod --since=10m
./bin/opsro k8s --context prod events -n prod
./bin/opsro k8s --context prod top pods -n prod
```

### 4. Optional host inspection

Create `opsro.json` from `examples/config.json`, install `brokers/host-readonly/readonly-broker.sh` on the target host, and use:

```bash
./bin/opsro host status web-01
./bin/opsro host logs web-01 nginx --since=10m --tail=200
./bin/opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
```

## Recommended Agent Usage

Tell the agent:

- use `opsro` for all production inspection
- do not call `kubectl` directly
- do not use any write-capable kubeconfig

For humans, `k9s --readonly` is a good complement. For agents, `opsro` is a better fit because it returns plain command output instead of an interactive TUI.

## Container Runtime

Two container paths are included:

- `Dockerfile`: a minimal read-only runtime with `opsro` and `kubectl`
- `Dockerfile.agent`: an agent runtime for Codex or Claude Code with `opsro` as the intended operations interface

In the agent image, `kubectl` and `ssh` are hidden behind `opsro` by default wrappers, while the real binaries live under `/opt/opsro/bin`.

The compose example mounts both a read-only kubeconfig and an `opsro` host inventory file via `OPSRO_CONFIG`.

## Project Layout

```text
cmd/opsro/                 CLI entrypoint
examples/rbac/             sample Kubernetes read-only RBAC
examples/config.json       sample host inventory config
brokers/host-readonly/     host-side broker script and ForceCommand notes
docs/                      architecture, security, quickstart, and container notes
docker/                    entrypoint and direct-command blockers for agent images
```

## Roadmap

### V1

- read-only K8s CLI
- sample RBAC
- sample host read-only broker
- host inventory config
- quickstart docs

### V2

- stronger agent runtime isolation
- log source adapters
- write request / approval flow
- optional MCP wrapper
```
