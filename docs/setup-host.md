# Setup Host Access for opsro

This guide explains how to prepare a host for read-only `opsro` access.

## Goal

Create a dedicated low-privilege SSH user whose sessions are forced into a read-only broker.

## Steps

### Recommended

```bash
curl -fsSL https://raw.githubusercontent.com/lzfxxx/opsro/main/scripts/install-host-broker.sh | sudo sh
```

By default this installs the broker to `/usr/local/bin/readonly-broker`, creates the `opsro` user if needed, writes an `sshd` config fragment (or managed block fallback), validates config, and reloads `sshd`.

Useful flags:

- `--user opsro`
- `--install-path /usr/local/bin/readonly-broker`
- `--inventory-name web-01`
- `--address 10.0.1.12`
- `--port 22`
- `--skip-reload`
- `--dry-run`

### Manual

1. Create a dedicated SSH user, for example `opsro`.
2. Install the broker:

```bash
sudo install -m 0755 brokers/host-readonly/readonly-broker.sh /usr/local/bin/readonly-broker
```

3. Add this block to `sshd_config`:

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

4. Restart `sshd`.
5. Create `opsro.json` from `examples/config.json` and mount it into the container.
6. Set:

```bash
OPSRO_CONFIG=/config/opsro.json
```

## Verify

```bash
opsro host status web-01
opsro host logs web-01 nginx --since=10m --tail=200
opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
```

## Notes

- the `opsro` SSH user should not have sudo
- the broker only allows a narrow read-only command set
- direct shell access should stay disabled for the `opsro` user
