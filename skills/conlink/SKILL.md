---
name: conlink
description: Declarative container networking tool for Docker Compose that provides precise L1/L2/L3 network simulation. Use when working with conlink configuration, docker-compose networking beyond standard Docker networks, container network simulation (packet loss, latency, jitter, bandwidth), VLAN/macvlan/ipvlan interfaces, network topology for testing, or questions about conlink features and syntax.
---

# Conlink

Conlink (container link) replaces standard Docker Compose networking with fine-grained control over layer 1-3 networking. It runs as a container service that listens to Docker events and creates network interfaces dynamically.

## Quick Start

Add conlink service and `x-network` configuration to compose file:

```yaml
services:
  network:
    image: lonocloud/conlink:latest
    pid: host
    network_mode: none
    cap_add: [SYS_ADMIN, NET_ADMIN, SYS_NICE, NET_BROADCAST, IPC_LOCK]
    security_opt: ['apparmor:unconfined']
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker:/var/lib/docker
      - ./:/app
    command: /app/build/conlink.js --compose-file /app/docker-compose.yaml

  node1:
    image: alpine
    cap_add: [NET_ADMIN]
    command: sh -c 'while ! ip link show eth0 up; do sleep 1; done; sleep infinity'

  node2:
    image: alpine
    cap_add: [NET_ADMIN]
    command: sh -c 'while ! ip link show eth0 up; do sleep 1; done; sleep infinity'

x-network:
  links:
    - {service: node1, bridge: net1, ip: "10.0.1.1/24"}
    - {service: node2, bridge: net1, ip: "10.0.1.2/24"}
```

## Key Concepts

**Links**: Network interfaces created in containers. Default type is `veth` (virtual ethernet pair).

**Bridges**: L2 switches connecting multiple links. Modes: `auto`, `ovs`, `linux`, `patch`.

**Tunnels**: Remote L2 connections via `geneve` or `vxlan`.

**Async startup**: Interfaces are created after container starts. Containers must wait for interfaces.

## Link Types

| Type | Use Case |
|------|----------|
| `veth` | Standard container networking (default) |
| `dummy` | Local-only interface, NAT scenarios |
| `vlan` | 802.1Q VLAN on host interface |
| `macvlan` | Direct host network access with unique MAC |
| `ipvlan` | Direct host network access, shared MAC |

## Common Link Properties

```yaml
- service: myservice       # Target service name
  bridge: net1             # L2 domain (required for veth)
  dev: eth0                # Interface name (default: eth0)
  ip: "10.0.1.1/24"        # IPv4 address
  mac: "00:0a:0b:0c:0d:01" # MAC address
  mtu: 1500                # MTU size
  route: "default via 10.0.1.254"  # Routing
  netem: "delay 50ms loss 1%"      # Network emulation
  forward: "8080:80/tcp"           # Port forwarding
```

## Network Emulation (netem)

Simulate network conditions:

```yaml
netem: "rate 10mbit"              # Bandwidth limit
netem: "delay 50ms"               # Latency (RTT = 2x)
netem: "delay 50ms 10ms"          # Latency with jitter
netem: "loss 5%"                  # Packet loss
netem: "duplicate 1%"             # Duplication
netem: "corrupt 0.1%"             # Corruption
netem: "rate 1mbit delay 100ms loss 2%"  # Combined
```

## Scaling

When services have `scale > 1`, IPs/MACs/ports auto-increment:

```yaml
services:
  worker:
    scale: 3

x-network:
  links:
    - service: worker
      bridge: cluster
      ip: 10.0.1.1/24        # .1, .2, .3
      mac: 00:0a:0b:0c:0d:01 # :01, :02, :03
```

## Wait Utility

Conlink provides `/utils/wait` for async startup:

```bash
/utils/wait -i eth0              # Wait for interface
/utils/wait -I eth0              # Wait for interface with IP
/utils/wait -t host:8080         # Wait for TCP port
/utils/wait -f /path/file        # Wait for file to exist
/utils/wait -c "command"         # Wait for command to succeed
/utils/wait -i eth0 -i eth1 -- cmd  # Wait for multiple interfaces
```

## Copy Utility (File Overlay & Templating)

Conlink provides `/utils/copy.sh` for overlaying config files at container startup without rebuilding images:

```bash
# Basic: copy /files/* onto root filesystem, then run app
/utils/copy.sh /files / -- /path/to/app

# With templating (-T): replace {{VAR}} with environment variables
/utils/copy.sh -T /files / -- /path/to/app
```

See [Configuration Reference](references/configuration.md#copy-utility) for detailed usage.

## References

- [Configuration Reference](references/configuration.md) - All properties for links, bridges, tunnels
- [Examples](references/examples.md) - Common patterns and complete compose examples
