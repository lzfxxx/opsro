# Quick Start

## Kubernetes Read-Only

1. Apply the sample RBAC from `examples/rbac/readonly-clusterrole.yaml`.
2. Generate a kubeconfig for that read-only identity.
3. Run:

```bash
make build
./bin/opsro k8s --context prod get pods -A
./bin/opsro k8s --context prod logs deployment/api -n prod --since=10m
```

## Host Read-Only

1. Copy `brokers/host-readonly/readonly-broker.sh` to the host as `/usr/local/bin/readonly-broker`.
2. Make it executable.
3. Create a low-privilege SSH user, for example `opsro`.
4. Add a `ForceCommand` block in `sshd_config`:

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

5. Restart `sshd`.
6. Copy `examples/config.json` to either:
   - `./opsro.json`, or
   - `~/.config/opsro/config.json`

7. Run:

```bash
./bin/opsro host status web-01
./bin/opsro host logs web-01 nginx --since=10m --tail=200
./bin/opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
```

## Notes

- The host broker is still intentionally narrow and read-only.
- Kubernetes safety comes from RBAC.
- Host safety comes from `ForceCommand` plus the broker allowlist.
