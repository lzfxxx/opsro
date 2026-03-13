# opsro

[English](README.md) | 简体中文

`opsro` 是一个**给 coding agent 用的只读运维 CLI**。

它的目标场景是：让 Codex / Claude Code 跑在隔离容器里，再通过 `opsro` 以一个更窄、更稳定、可控的接口去查看 Kubernetes 和宿主机。

## 这个项目是干什么的

适合这样的场景：

- 让 agent 用只读 kubeconfig 查看 Kubernetes
- 让 agent 通过只读 SSH broker 查看宿主机
- 在故障排查时读取日志和运行时状态
- 避免直接暴露通用 shell 和大范围凭证

## 1. 先准备后端访问能力

`opsro` 只是给 agent 调用的 CLI，真正的安全边界仍然在后端。

### 最省事的路径

直接用 bootstrap 脚本，一次性产出 `kubeconfig.opsro`、`opsro.json` 和可运行的 agent 启动脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/bootstrap.sh | sh -s -- \
  --out-dir ./opsro-bootstrap \
  --host-name web-01 \
  --host-address 10.0.1.12
```

当前这个 MVP 版本里，K8s 会直接执行安装；Host 现在支持三种模式：

- 默认生成一个本地 helper 脚本
- 用 `--install-host-local` 在当前机器直接安装
- 用 `--install-host-remote --remote-host ...` 从管理节点通过 SSH 远程安装

### Kubernetes

先安装只读 RBAC，并为这个身份生成 kubeconfig：

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install-k8s-readonly.sh | sh
```

底层示例清单仍然保留在 `examples/rbac/readonly-clusterrole.yaml`。

### 宿主机

先在目标宿主机安装只读 broker：

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install-host-broker.sh | sudo sh
```

或者直接让 `bootstrap.sh` 从管理节点通过 SSH 推过去安装：

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/bootstrap.sh | sh -s -- \
  --out-dir ./opsro-bootstrap \
  --host-name web-01 \
  --host-address 10.0.1.12 \
  --install-host-remote \
  --remote-host 10.0.1.12 \
  --remote-ssh-user admin
```

然后再按 `examples/config.json` 配置 host inventory，或者直接使用 bootstrap 输出目录里生成的 `opsro.json`。

完整逐步说明和高级参数见 `docs/quickstart.md`。

## 2. 运行 agent 容器

先拉镜像：

```bash
docker pull ghcr.io/lzfxxx/opsro-codex:latest
docker pull ghcr.io/lzfxxx/opsro-claude:latest
```

两个 agent 镜像都默认需要：

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

如果**不传** API key 环境变量，Codex 就会回到自己的交互式登录流程。想保留登录状态，就把 `/root/.codex` 挂出来。

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

## 3. 在容器里使用 opsro

```bash
opsro k8s --context prod get pods -A
opsro k8s --context prod logs deployment/api -n prod --since=10m
opsro host status web-01
opsro host logs web-01 nginx --since=10m --tail=200
```

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

- 从管理节点直接远程打通 Host Broker，而不是先生成本地 helper
- 更强的运行时隔离和策略控制
- 更丰富的运维原语：日志 / 指标 / trace
- 面向敏感动作的审批和审计链路

## 可选内容

- `examples/docker-compose.agent.yml`：如果你想保留一个可复用模板
- `scripts/install.sh`：如果你想在本机单独安装裸 `opsro` CLI
- `docs/bootstrap.md`、`docs/containers.md`、`docs/quickstart.md`、`examples/`：查看更完整的细节
