# opsro

[English](README.md) | 简体中文

`opsro` 是一个面向 AI agent 和人工运维的只读运维 CLI。

它的目标是给 `Codex`、`Claude Code` 和人工操作员一个更窄、更安全的生产排查入口，而不是直接把通用 shell、`kubectl` 或 `ssh` 暴露给它们。

## 它是干什么的

`opsro` 适合这样的场景：

- 希望 agent 安全查看 Kubernetes 集群状态
- 希望 agent 能读取日志和运行时状态
- 希望 agent 能参与生产故障排查
- 希望 agent 能通过只读 broker 查看宿主机
- 不希望 agent 直接拿到 `kubectl`、`ssh` 和大范围凭证

V1 明确只做只读能力。

## 它不是什么

`opsro` 不是：

- 一个完整的 agent 平台
- 一个审批流引擎
- Kubernetes RBAC 的替代品
- 宿主机变更执行框架
- 一个通用 shell 沙箱

真正的权限边界仍然在后端系统：

- 集群侧靠 Kubernetes RBAC
- 宿主机侧靠 SSH `ForceCommand` + allowlist broker
- agent 运行时侧靠容器隔离

## 工作原理

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

对 Kubernetes 来说：

- `opsro` 内部调用 `kubectl`
- `kubectl` 使用单独的只读 kubeconfig
- 真正的权限控制由 Kubernetes RBAC 完成

对宿主机来说：

- `opsro` 内部调用 `ssh`
- 宿主机上的 `opsro` 用户被 `ForceCommand` 强制接入 `readonly-broker`
- broker 只允许固定的只读命令

## 为什么不用原生 kubectl 或 ssh

其实 Kubernetes 只读访问本来就可以用 `kubectl + RBAC` 做到。

`opsro` 的价值主要在于把 agent 的操作面统一起来：

- Kubernetes 和宿主机都走同一个 CLI 入口
- 命令面更小、更稳定
- 后面加日志、审批、运行时限制时，不用改 agent 的调用方式
- agent 容器里可以把直接 `kubectl` 和 `ssh` 挡掉，强制走 `opsro`

## V1 已有能力

- `opsro k8s get`
- `opsro k8s describe`
- `opsro k8s logs`
- `opsro k8s events`
- `opsro k8s top`
- `opsro host status`
- `opsro host logs`
- `opsro host run`
- Kubernetes 只读 RBAC 示例
- 宿主机只读 broker 示例
- 面向 Codex 和 Claude Code 的容器镜像
- CLI 和容器的 release 自动化

## 安装方式

### CLI

本地编译：

```bash
make build
```

也可以直接从 GitHub Releases 下载二进制包。

### 容器

基础运行时镜像：

```bash
docker pull ghcr.io/lzfxxx/opsro:latest
# 或固定版本
# docker pull ghcr.io/lzfxxx/opsro:<version>
```

Codex 运行时镜像：

```bash
docker pull ghcr.io/lzfxxx/opsro-codex:latest
# 或固定版本
# docker pull ghcr.io/lzfxxx/opsro-codex:<version>
```

Claude Code 运行时镜像：

```bash
docker pull ghcr.io/lzfxxx/opsro-claude:latest
# 或固定版本
# docker pull ghcr.io/lzfxxx/opsro-claude:<version>
```

## 快速开始

### 1. 准备只读 kubeconfig

先应用 `examples/rbac/readonly-clusterrole.yaml` 里的示例 RBAC，然后为这个只读身份生成 kubeconfig。

### 2. 编译 CLI

```bash
make build
```

### 3. 查看 Kubernetes

```bash
./bin/opsro k8s --context prod get pods -A
./bin/opsro k8s --context prod describe deployment api -n prod
./bin/opsro k8s --context prod logs deployment/api -n prod --since=10m
./bin/opsro k8s --context prod events -n prod
./bin/opsro k8s --context prod top pods -n prod
```

### 4. 可选：查看宿主机

把 `examples/config.json` 复制成 `opsro.json`，把 `brokers/host-readonly/readonly-broker.sh` 安装到目标宿主机后，可以执行：

```bash
./bin/opsro host status web-01
./bin/opsro host logs web-01 nginx --since=10m --tail=200
./bin/opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
```

更完整的步骤见 `docs/quickstart.md`。

补充配置文档：

- `docs/setup-k8s.md`
- `docs/setup-host.md`

## 给 Agent 的推荐用法

建议在提示词或 skill 里明确要求 agent：

- 所有生产排查都通过 `opsro`
- 不要直接调用 `kubectl`
- 不要直接调用 `ssh`
- 不要使用任何具备写权限的 kubeconfig

这对 `Codex` 和 `Claude Code` 这种代码型 agent 特别有用，因为你通常希望它们有能力排查，但又不想直接放开系统级命令面。

## Agent 容器

仓库里有两种容器路径：

- `Dockerfile`：最小只读运行时，包含 `opsro` 和 `kubectl`
- `Dockerfile.agent`：给 Codex 或 Claude Code 用的 agent 运行时

在 agent 镜像里：

- 直接执行 `kubectl` 会被拦截
- 直接执行 `ssh` 会被拦截
- 真实二进制放在 `/opt/opsro/bin`
- `opsro` 通过 `OPSRO_KUBECTL` 和 `OPSRO_SSH` 去调用它们

容器示例：

- `examples/docker-compose.agent.yml`

推荐挂载：

- 只读 kubeconfig
- `opsro` 宿主机 inventory 配置
- agent 自己的工作目录

agent 镜像首次启动时，如果 `/workspace` 下缺少这些文件，会自动写入：

- `AGENTS.md`
- `CLAUDE.md`
- `ONBOARD.md`
- `SETUP_K8S.md`
- `SETUP_HOST.md`
- `opsro.json.example`

## 安全模型

`opsro` 只是在客户端侧收窄命令面，不会替代后端权限系统。

Kubernetes 的安全边界来自：

- 独立的只读 kubeconfig
- Kubernetes RBAC
- 避免把写权限凭证给 agent

宿主机的安全边界来自：

- 独立低权限 SSH 用户
- `ForceCommand`
- `readonly-broker`
- 严格的只读命令 allowlist

如果你需要写操作和审批流，那属于 V2 范围。

## 发布方式

打一个版本 tag，就会自动发布 CLI 二进制和容器镜像：

```bash
git tag v0.3.0
git push origin v0.3.0
```

仓库里已经包含：

- `.goreleaser.yaml`：发布 GitHub Releases
- `.github/workflows/release.yml`：发布 CLI 二进制
- `.github/workflows/containers.yml`：发布 GHCR 镜像

## 项目结构

```text
cmd/opsro/                 CLI 入口
examples/rbac/             Kubernetes 只读 RBAC 示例
examples/config.json       宿主机 inventory 配置示例
examples/docker-compose.agent.yml
                           本地 Codex 和 Claude Code 容器示例
brokers/host-readonly/     宿主机 broker 脚本和 ForceCommand 说明
docs/                      架构、安全、快速开始、容器说明
docker/                    agent 镜像入口和直接命令拦截脚本
.github/workflows/         CLI 和容器的发布自动化
```

## 文档与模板

仓库文档：

- `docs/quickstart.md`
- `docs/setup-k8s.md`
- `docs/setup-host.md`
- `docs/containers.md`

镜像内模板：

- `/workspace/AGENTS.md`
- `/workspace/CLAUDE.md`
- `/workspace/ONBOARD.md`
- `/workspace/SETUP_K8S.md`
- `/workspace/SETUP_HOST.md`
- `/workspace/opsro.json.example`

## 当前状态

当前进度：

- Kubernetes 只读链路：可用
- 宿主机只读链路：最小可用
- Agent 容器：可用
- 写操作和审批流：尚未实现

## 后续路线

### V1

- 只读 K8s CLI
- RBAC 示例
- 宿主机只读 broker 示例
- host inventory 配置
- quickstart 文档
- release 自动化

### V2

- 更强的 agent runtime 隔离
- 日志源适配
- 写操作申请和审批流
- 可选 MCP 封装
