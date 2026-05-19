# Conlink Configuration Reference

## Table of Contents

1. [Configuration Sources](#configuration-sources)
2. [Top-Level Keys](#top-level-keys)
3. [Link Configuration](#link-configuration)
4. [Bridge Configuration](#bridge-configuration)
5. [Tunnel Configuration](#tunnel-configuration)
6. [Commands Configuration](#commands-configuration)
7. [Auto-Incrementing](#auto-incrementing)
8. [Copy Utility](#copy-utility)

## Configuration Sources

Network configuration can come from multiple sources:

1. **Embedded in compose files** using `x-network` top-level key
2. **Embedded in service definitions** using `x-network` service property
3. **Separate network config files** via `--network-file` option
4. **Multiple sources merged together** (colon-separated paths)

## Top-Level Keys

```yaml
x-network:
  links: []      # Array of link definitions
  bridges: []    # Array of bridge configurations
  tunnels: []    # Array of tunnel definitions
  commands: []   # Array of commands to execute
```

## Link Configuration

### Identification Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `service` | string | - | Docker Compose service name |
| `container` | string | - | Fully qualified container name (alternative to service) |
| `dev` | string | `eth0` | Interface name in container (max 15 chars) |

### Link Types

| Type | Description | Required Properties |
|------|-------------|---------------------|
| `veth` | Virtual ethernet pair (default) | `bridge` |
| `dummy` | Dummy interface, no external connection | - |
| `vlan` | 802.1Q VLAN subinterface | `outer-dev`, `vlanid` |
| `ipvlan` | IP VLAN interface | `outer-dev`, `mode` |
| `macvlan` | MAC VLAN interface | `outer-dev`, `mode` |
| `ipvtap` | TAP version of IP VLAN | `outer-dev`, `mode` |
| `macvtap` | TAP version of MAC VLAN | `outer-dev`, `mode` |

### Layer 2 Properties

| Property | Type | Description |
|----------|------|-------------|
| `bridge` | string | Bridge name for veth links |
| `mac` | string | MAC address (e.g., `00:0a:0b:0c:0d:01`) |
| `outer-dev` | string | Host interface for *vlan types |
| `vlanid` | number | VLAN ID (0-4095) for vlan type |
| `mode` | string | Mode for *vlan types: `bridge`, `vepa`, `private`, `passthru`, `l2` |

### Layer 3 Properties

| Property | Type | Description |
|----------|------|-------------|
| `ip` | string | IPv4 CIDR address (e.g., `10.0.1.1/24`) |
| `route` | string/array | Route specs for `ip route add` |
| `nat` | string | IP for stateless DNAT/SNAT (requires `ip`) |

### Link Characteristics

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `mtu` | number | 65535 | Maximum Transmission Unit |
| `netem` | string/array | - | tc qdisc network emulation |
| `ethtool` | string/array | - | ethtool settings |
| `forward` | string/array | - | Port forwarding (veth only) |

### netem Options

Network emulation using tc qdisc:

```yaml
netem: "rate 10mbit"           # Bandwidth limiting
netem: "delay 40ms"            # Latency (RTT = delay * 2)
netem: "loss 5%"               # Packet loss
netem: "duplicate 2%"          # Packet duplication
netem: "corrupt 1%"            # Packet corruption
netem: "delay 40ms 5ms"        # Latency with jitter
netem: "rate 10mbit delay 40ms loss 1%"  # Combined
```

### ethtool Options

```yaml
ethtool: "--offload rx off"
ethtool: "--offload tx off"
ethtool: ["--offload rx off", "--offload tx off"]
```

### Port Forwarding

Format: `conlink_port:container_port/protocol`

```yaml
forward: "1080:80/tcp"
forward: ["1080:80/tcp", "1443:443/tcp"]
```

### Base Namespace

| Value | Description |
|-------|-------------|
| `:conlink` | In conlink namespace (default for veth) |
| `:host` | In host namespace (default for *vlan) |
| `:local` | In link's own namespace (default for others) |

## Bridge Configuration

```yaml
bridges:
  - bridge: <name>
    mode: <mode>
```

### Bridge Modes

| Mode | Description |
|------|-------------|
| `auto` | Select OVS if available, else Linux bridge (default) |
| `ovs` | Open vSwitch (requires openvswitch module) |
| `linux` | Native Linux kernel bridge |
| `patch` | Direct connection between exactly 2 links |

## Tunnel Configuration

```yaml
tunnels:
  - type: <geneve|vxlan>
    bridge: <bridge-name>
    remote: <remote-ip>
    vni: <0-16777215>
    netem: <optional-netem>
```

| Property | Description |
|----------|-------------|
| `type` | `geneve` (UDP 6081) or `vxlan` (UDP 4789/8472) |
| `bridge` | Bridge to attach tunnel to |
| `remote` | Remote host IP address |
| `vni` | Virtual Network Identifier |
| `netem` | Optional network emulation on tunnel |

## Commands Configuration

Execute commands after links are created:

```yaml
commands:
  - service: <service-name>
    command: "shell command"
  - container: <container-name>
    command: ["cmd", "arg1", "arg2"]
```

## Auto-Incrementing

When services have multiple replicas, values auto-increment:

| Property | Example | Replica 1 | Replica 2 | Replica 3 |
|----------|---------|-----------|-----------|-----------|
| `ip` | `10.0.1.1/24` | `.1` | `.2` | `.3` |
| `mac` | `00:0a:0b:0c:0d:01` | `:01` | `:02` | `:03` |
| `forward` | `1080:80/tcp` | `1080` | `1081` | `1082` |

## Copy Utility

The conlink container includes `/utils/copy.sh` for overlaying configuration files onto containers at startup. This enables runtime configuration without rebuilding images.

### Basic Usage

```yaml
services:
  myapp:
    volumes:
      - ./conlink/scripts:/scripts:ro    # Mount copy.sh
      - ./.files/myapp:/files:ro         # Mount overlay files
    command: /scripts/copy.sh /files / -- /path/to/myapp args
```

The copy.sh script:
1. Recursively copies all files from `/files` onto the root filesystem `/`
2. Preserves directory structure (e.g., `/files/etc/app.conf` → `/etc/app.conf`)
3. Executes the command after `--`

### Templating (-T flag)

With `-T`, copy.sh replaces `{{VAR}}` placeholders with environment variable values:

```yaml
services:
  myapp:
    environment:
      - TARGET_HOST=${BACKEND_IP}
      - TARGET_PORT=8080
    volumes:
      - ./conlink/scripts:/scripts:ro
      - ./.files/myapp:/files:ro
    command: /scripts/copy.sh -T /files / -- /path/to/myapp
```

Template file (`files/etc/myapp.conf`):
```
server = {{TARGET_HOST}}:{{TARGET_PORT}}
```

After copy with `-T`, `/etc/myapp.conf` contains the resolved values.

### Multi-Module File Composition

When using a module composition system (like mdc), files from later modules override earlier ones:

```
# Module A (base)
modes/moduleA/myapp/files/etc/myapp.conf      # Base config
modes/moduleA/myapp/files/etc/myapp/db.conf   # DB settings

# Module B (override, depends on A)
modes/moduleB/myapp/files/etc/myapp.conf      # Overrides base config
modes/moduleB/myapp/files/etc/myapp/cache.conf # Adds new file
```

The composition tool merges these into `.files/myapp/`, with later modules winning conflicts.

### Combining with Wait Utility

Common pattern - wait for interfaces, then copy files, then start:

```yaml
command: >
  /utils/wait -i eth0 --
  /scripts/copy.sh -T /files / --
  /path/to/myapp --config /etc/myapp.conf
```

Or chain wait inside copy.sh's command:

```yaml
command: /scripts/copy.sh -T /files / -- /utils/wait -i eth0 -- /path/to/myapp
```
