# Quick Start

## Kubernetes Read-Only

1. Run:

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install-k8s-readonly.sh | sh
```

2. Mount the generated kubeconfig into the agent container.
3. Run:

```bash
make build
./bin/opsro k8s --context prod get pods -A
./bin/opsro k8s --context prod logs deployment/api -n prod --since=10m
```

## Host Read-Only

1. Run on the target host:

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install-host-broker.sh | sudo sh
```

2. If you want the manual path instead, install the broker and add a `ForceCommand` block in `sshd_config`:

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

3. Restart `sshd` if you used the manual path.
4. Copy `examples/config.json` to either:
   - `./opsro.json`, or
   - `~/.config/opsro/config.json`

5. Run:

```bash
./bin/opsro host status web-01
./bin/opsro host logs web-01 nginx --since=10m --tail=200
./bin/opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
```

## Notes

- The host broker is still intentionally narrow and read-only.
- Kubernetes safety comes from RBAC.
- Host safety comes from `ForceCommand` plus the broker allowlist.
