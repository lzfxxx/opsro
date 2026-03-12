# opsro

[English](README.md) | 简体中文

`opsro` 是一个给 AI agent 和人工运维使用的**只读运维 CLI**。

它的目标不是把通用 shell、`kubectl`、`ssh` 直接交给 Codex / Claude Code，而是给它们一个更窄、更稳定、可控的生产排查入口。

## 这个项目是干什么的

适合这样的场景：

- 让 agent 用只读 kubeconfig 安全查看 Kubernetes
- 让 agent 通过只读 SSH broker 查看宿主机
- 在故障排查时读取日志和运行时状态
- 避免直接暴露大范围凭证和通用 shell

## 快速开始

先拉镜像：

```bash
docker pull ghcr.io/lzfxxx/opsro-codex:latest
docker pull ghcr.io/lzfxxx/opsro-claude:latest
```

两个镜像都默认需要：

- `KUBECONFIG=/config/kubeconfig`
- `OPSRO_CONFIG=/config/opsro.json`
- 把只读 kubeconfig 挂到 `/config/kubeconfig`
- 把 `opsro` inventory 挂到 `/config/opsro.json`
- 把工作目录挂到 `/workspace`

### Codex

如果传了 `OPENAI_API_KEY`，并且 Codex 当前还没登录，`opsro-codex` 的 entrypoint 会自动执行：

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

如果**不传** API key 相关环境变量，Codex 就会回到它自己的交互式登录流程。想保留登录状态，就把 `/root/.codex` 挂出来。

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

如果**不传** API key 环境变量，就走一次 OAuth，并把配置目录持久化：

```bash
docker run --rm -it \
  -e KUBECONFIG=/config/kubeconfig \
  -e OPSRO_CONFIG=/config/opsro.json \
  -v $(pwd)/kubeconfig:/config/kubeconfig:ro \
  -v $(pwd)/opsro.json:/config/opsro.json:ro \
  -v $(pwd)/workspace:/workspace \
  -v opsro-claude-config:/root/.config \
  ghcr.io/lzfxxx/opsro-claude:latest

# 进入容器后
claude login
```

可直接参考：

- `examples/docker-compose.agent.yml`
- `examples/.env.codex.example`
- `examples/.env.claude.example`

## Kubernetes RBAC

先应用只读 RBAC 示例，再为这个只读身份生成 kubeconfig：

- `examples/rbac/readonly-clusterrole.yaml`

之后就可以这样用：

```bash
./bin/opsro k8s --context prod get pods -A
./bin/opsro k8s --context prod logs deployment/api -n prod --since=10m
```

## 宿主机 Read-Only Broker

在目标宿主机上：

1. 把 `brokers/host-readonly/readonly-broker.sh` 安装到 `/usr/local/bin/readonly-broker`
2. 创建一个低权限 SSH 用户，比如 `opsro`
3. 用 SSH `ForceCommand` 把这个用户强制接入 broker
4. 按 `examples/config.json` 配置 inventory

之后就可以这样用：

```bash
./bin/opsro host status web-01
./bin/opsro host logs web-01 nginx --since=10m --tail=200
./bin/opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
```

`ForceCommand` 的完整示例可以看 `docs/quickstart.md`。

## 机制简述

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

- Kubernetes 的安全边界来自 RBAC
- 宿主机的安全边界来自 `ForceCommand` + 只读 allowlist broker
- 容器镜像做的是收窄本地工具面：直接 `kubectl` / `ssh` 会被挡掉，但它并不替代后端授权

## Roadmap

- 更强的运行时隔离和策略控制
- 更丰富的运维原语：日志 / 指标 / trace
- 面向敏感动作的审批和审计链路
- 更好的多集群、多宿主机使用体验

更多细节可以看：

- `docs/quickstart.md`
- `docs/containers.md`
- `examples/`
