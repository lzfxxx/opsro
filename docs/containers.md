# Agent Containers

`Dockerfile.agent` builds an agent runtime that includes:

- `opsro`
- a selected agent CLI (`Codex` or `Claude Code`)
- hidden `kubectl`
- hidden `ssh`

## Why a Separate Agent Image?

The plain `Dockerfile` is a narrow runtime for `opsro` itself.

`Dockerfile.agent` adds the AI agent CLI while keeping the production inspection surface narrow.

## Hidden Tool Pattern

Inside the agent image:

- the real `kubectl` lives at `/opt/opsro/bin/kubectl`
- the real `ssh` lives at `/opt/opsro/bin/ssh`
- `opsro` uses these via `OPSRO_KUBECTL` and `OPSRO_SSH`
- direct `kubectl` and direct `ssh` in `PATH` are replaced with wrappers that fail fast

This is not a perfect sandbox, but it strongly nudges the agent toward `opsro` as the operational interface.

The Dockerfiles also work with plain `docker build`, not only BuildKit, by falling back to `uname -m` when `TARGETARCH` is not set.

## Build Examples

### Codex image

```bash
docker build -f Dockerfile.agent \
  --build-arg AGENT_PACKAGE=@openai/codex \
  --build-arg AGENT_BIN=codex \
  -t opsro-codex:dev .
```

### Claude Code image

```bash
docker build -f Dockerfile.agent \
  --build-arg AGENT_PACKAGE=@anthropic-ai/claude-code \
  --build-arg AGENT_BIN=claude \
  -t opsro-claude:dev .
```

## Authentication

### Codex

Codex is typically configured with environment variables:

- `OPENAI_API_KEY`
- `OPENAI_BASE_URL` for OpenAI-compatible gateways

Use `examples/.env.codex.example` as a starting point.

### Claude Code

Claude Code can be configured in two common ways:

1. API key mode through environment variables
   - `ANTHROPIC_API_KEY`
   - optionally `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` when using a compatible gateway
2. OAuth / interactive login inside the container
   - mount a persistent config directory such as `/root/.config`
   - run `claude login` once inside the container

Use `examples/.env.claude.example` as a starting point for API-key mode.

## Compose Example

See `examples/docker-compose.agent.yml`.

Expected mounts:

- a dedicated read-only kubeconfig
- an `opsro` config file with host inventory
- a writable working directory for the agent itself

On first start, the agent image seeds these files into `/workspace` if they do not already exist:

- `AGENTS.md`
- `CLAUDE.md`
- `ONBOARD.md`
- `SETUP_K8S.md`
- `SETUP_HOST.md`
- `opsro.json.example`

Recommended environment:

- `KUBECONFIG=/config/kubeconfig`
- `OPSRO_CONFIG=/config/opsro.json`

## Notes

- Kubernetes safety still comes from RBAC.
- Host safety still comes from `ForceCommand` and the host broker allowlist.
- The container only narrows the local tool surface; it does not replace backend authorization.
- If you use OAuth for Claude Code, keep the mounted config volume persistent across restarts.
