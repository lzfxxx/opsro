# Host Read-Only Broker

This directory holds the host-side design for V2.

V1 does not ship host execution yet. The goal is to keep the first release focused on Kubernetes read-only inspection.

## Recommended Direction

- dedicate a low-privilege SSH user such as `opsro`
- use `ForceCommand` to route every SSH session into a broker program
- do not give the account an interactive shell
- allow only a whitelist of read-only commands
- reject shell metacharacters and string-based command execution

## Candidate Allowlist

- `journalctl --no-pager`
- `systemctl status`
- `ps`
- `ss`
- `df`
- `free`
- `uptime`
- `uname`
- `ls`
- `cat`
- `tail`
- `head`
- `grep` / `rg`

## Commands To Exclude

- any shell (`bash`, `sh`, `zsh`)
- `sudo`
- editors and pagers (`vim`, `nano`, `less`, `more`)
- language runtimes used for arbitrary execution (`python -c`, `node -e`, etc.)

## Example sshd_config Block

```sshconfig
Match User opsro
    ForceCommand /usr/local/bin/readonly-broker
    PermitTTY no
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
    GatewayPorts no
    PermitUserEnvironment no
```
