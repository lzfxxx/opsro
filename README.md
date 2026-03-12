# opsro

English | [简体中文](README.zh-CN.md)

`opsro` is a read-only operations CLI for AI agents and humans.

It gives `Codex`, `Claude Code`, and human operators a narrow command surface for production inspection without handing them a general-purpose shell.

## What It Is

`opsro` is designed for the common setup where you want an agent to:

- inspect Kubernetes clusters safely
- read logs and runtime state
- investigate incidents in production
- inspect hosts through a read-only broker
- avoid direct use of `kubectl`, `ssh`, and broad credentials

V1 is intentionally focused on read-only operations.

## What It Is Not

`opsro` is not:

- a full agent platform
- an approval workflow engine
- a replacement for Kubernetes RBAC
- a host mutation framework
- a general shell sandbox

The real permission boundaries still live in your backend systems:

- Kubernetes RBAC for clusters
- SSH `ForceCommand` plus an allowlist broker for hosts
- container isolation for agent runtime constraints

## How It Works

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

For Kubernetes:

- `opsro` shells out to `kubectl`
- `kubectl` uses a dedicated read-only kubeconfig
- Kubernetes RBAC is the real enforcement boundary

For hosts:

- `opsro` shells out to `ssh`
- the host-side `opsro` user is forced into `readonly-broker`
- the broker only allows a fixed set of read-only commands

## Why Use opsro Instead of Raw kubectl or ssh?

You can already do read-only Kubernetes access with `kubectl + RBAC`.

`opsro` adds value by standardizing the operator interface for agents:

- one CLI contract for Kubernetes and hosts
- a smaller and more predictable command surface
- a path to layer on logs, approvals, and stricter runtime controls later
- agent containers that hide direct `kubectl` and `ssh` behind `opsro`

## Features in V1

- `opsro k8s get`
- `opsro k8s describe`
- `opsro k8s logs`
- `opsro k8s events`
- `opsro k8s top`
- `opsro host status`
- `opsro host logs`
- `opsro host run`
- sample read-only Kubernetes RBAC
- sample host read-only broker
- agent container images for Codex and Claude Code
- release automation for CLI binaries and containers

## Install

### CLI

Build locally:

```bash
make build
```

Or download a release artifact from GitHub Releases.

### Containers

Base runtime image:

```bash
docker pull ghcr.io/lzfxxx/opsro:latest
# or pin a version
# docker pull ghcr.io/lzfxxx/opsro:<version>
```

Codex runtime image:

```bash
docker pull ghcr.io/lzfxxx/opsro-codex:latest
# or pin a version
# docker pull ghcr.io/lzfxxx/opsro-codex:<version>
```

Claude Code runtime image:

```bash
docker pull ghcr.io/lzfxxx/opsro-claude:latest
# or pin a version
# docker pull ghcr.io/lzfxxx/opsro-claude:<version>
```

## Quick Start

### 1. Prepare a read-only kubeconfig

Apply the sample RBAC from `examples/rbac/readonly-clusterrole.yaml` and generate a kubeconfig for that read-only identity.

### 2. Build the CLI

```bash
make build
```

### 3. Inspect Kubernetes

```bash
./bin/opsro k8s --context prod get pods -A
./bin/opsro k8s --context prod describe deployment api -n prod
./bin/opsro k8s --context prod logs deployment/api -n prod --since=10m
./bin/opsro k8s --context prod events -n prod
./bin/opsro k8s --context prod top pods -n prod
```

### 4. Optional host inspection

Create `opsro.json` from `examples/config.json`, install `brokers/host-readonly/readonly-broker.sh` on the target host, and run:

```bash
./bin/opsro host status web-01
./bin/opsro host logs web-01 nginx --since=10m --tail=200
./bin/opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
```

A fuller walkthrough is in `docs/quickstart.md`.

## Example Agent Usage

Recommended instruction for an agent:

- use `opsro` for all production inspection
- do not call `kubectl` directly
- do not call `ssh` directly
- do not use any write-capable kubeconfig

This is especially useful for Codex and Claude Code, where you want a strong convention and a smaller operational surface.

## Agent Containers

Two container paths are included:

- `Dockerfile`: minimal runtime with `opsro` and `kubectl`
- `Dockerfile.agent`: agent runtime for Codex or Claude Code

In the agent image:

- direct `kubectl` is blocked
- direct `ssh` is blocked
- the real binaries live under `/opt/opsro/bin`
- `opsro` calls them through `OPSRO_KUBECTL` and `OPSRO_SSH`

Example compose file:

- `examples/docker-compose.agent.yml`

Expected mounts:

- read-only kubeconfig
- `opsro` host inventory config
- writable workspace for the agent itself

## Security Model

`opsro` narrows the client interface. It does not replace backend authorization.

Kubernetes safety comes from:

- a dedicated read-only kubeconfig
- Kubernetes RBAC
- avoiding direct write-capable credentials

Host safety comes from:

- a dedicated low-privilege SSH user
- `ForceCommand`
- `readonly-broker`
- a strict allowlist of read-only commands

If you need write operations and approvals, that belongs in V2.

## Release

Tag a version to publish both CLI artifacts and container images:

```bash
git tag v0.3.0
git push origin v0.3.0
```

This repository includes:

- `.goreleaser.yaml` for GitHub Releases
- `.github/workflows/release.yml` for CLI binaries
- `.github/workflows/containers.yml` for GHCR images

## Project Layout

```text
cmd/opsro/                 CLI entrypoint
examples/rbac/             sample Kubernetes read-only RBAC
examples/config.json       sample host inventory config
examples/docker-compose.agent.yml
                           local Codex and Claude Code container example
brokers/host-readonly/     host-side broker script and ForceCommand notes
docs/                      architecture, security, quickstart, and container notes
docker/                    entrypoint and direct-command blockers for agent images
.github/workflows/         release automation for CLI and containers
```

## Status

Current status:

- Kubernetes read-only flow: usable
- Host read-only flow: minimal but usable
- Agent containers: usable
- Write actions and approval flow: not implemented yet

## Roadmap

### V1

- read-only K8s CLI
- sample RBAC
- sample host read-only broker
- host inventory config
- quickstart docs
- release automation

### V2

- stronger agent runtime isolation
- log source adapters
- write request and approval flow
- optional MCP wrapper
