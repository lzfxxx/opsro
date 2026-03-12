# SETUP_HOST.md

This guide explains how to prepare a host for read-only `opsro` access.

## Goal

Create a dedicated low-privilege SSH path where all sessions are forced into a read-only broker.

## 1. Create a dedicated SSH user

Example:

```bash
sudo useradd -m -s /bin/sh opsro
```

This user should:

- not be an administrator
- not have sudo rights
- only be used for read-only inspection

## 2. Install the broker

Copy the script to the host:

```bash
sudo install -m 0755 brokers/host-readonly/readonly-broker.sh /usr/local/bin/readonly-broker
```

## 3. Configure SSH ForceCommand

Add a block like this to `sshd_config`:

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

Then restart `sshd`.

## 4. Prepare the local host inventory

Create `opsro.json` from `examples/config.json` and define host aliases.

Example:

```json
{
  "hosts": {
    "web-01": {
      "address": "10.0.1.12",
      "user": "opsro",
      "port": 22
    }
  }
}
```

Mount this file into the container and set:

```bash
OPSRO_CONFIG=/config/opsro.json
```

## 5. Verify the broker

From inside the `opsro` environment:

```bash
opsro host status web-01
opsro host logs web-01 nginx --since=10m --tail=200
opsro host run web-01 -- journalctl -u nginx --since=10m --no-pager
```

## Notes

- the broker intentionally allows only a small set of read-only commands
- `opsro host run` is still constrained by the host-side allowlist
- do not give the `opsro` host user sudo access
- do not allow interactive shell access outside the broker
