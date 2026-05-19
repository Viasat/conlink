# Conlink Examples

## Table of Contents

1. [Basic Two-Container Network](#basic-two-container-network)
2. [Multi-Interface Router](#multi-interface-router)
3. [Network Emulation](#network-emulation)
4. [Port Forwarding](#port-forwarding)
5. [Host-to-Container Port Forwarding](#host-to-container-port-forwarding)
6. [Scaled Services](#scaled-services)
7. [VLAN Configuration](#vlan-configuration)
8. [Remote Tunnels](#remote-tunnels)
9. [Bridge Modes](#bridge-modes)
10. [Service-Level x-network](#service-level-x-network)
11. [Interface Bonding and Redundancy](#interface-bonding-and-redundancy)
12. [MAC Address Conventions](#mac-address-conventions)
13. [Complete Compose Example](#complete-compose-example)
14. [Async Startup Pattern](#async-startup-pattern)
15. [Hybrid Docker + Conlink Networking](#hybrid-docker--conlink-networking)
16. [Multiple Routes](#multiple-routes)

## Basic Two-Container Network

Two containers on the same L2 segment:

```yaml
x-network:
  links:
    - {service: node1, bridge: net1, ip: "10.0.1.1/24"}
    - {service: node2, bridge: net1, ip: "10.0.1.2/24"}
```

## Multi-Interface Router

Router connecting two networks:

```yaml
x-network:
  links:
    - {service: router, bridge: lan, dev: eth0, ip: "10.0.1.1/24"}
    - {service: router, bridge: wan, dev: eth1, ip: "10.0.2.1/24"}
    - {service: client, bridge: lan, ip: "10.0.1.10/24", route: "default via 10.0.1.1"}
    - {service: server, bridge: wan, ip: "10.0.2.10/24", route: "default via 10.0.2.1"}
```

## Network Emulation

Simulate WAN conditions:

```yaml
x-network:
  links:
    - service: client
      bridge: wan
      ip: 10.0.1.1/24
      netem: "rate 10mbit delay 50ms loss 1%"
      mtu: 1500
      mac: "00:0a:0b:0c:0d:01"
      ethtool: "--offload rx off"
```

Multiple netem rules:

```yaml
netem:
  - "rate 1mbit"
  - "delay 100ms 20ms"  # 100ms delay with 20ms jitter
  - "loss 5%"
```

## Port Forwarding

Expose container ports through conlink:

```yaml
x-network:
  links:
    - service: webserver
      bridge: net1
      ip: 10.0.1.1/24
      forward:
        - "8080:80/tcp"
        - "8443:443/tcp"
```

## Host-to-Container Port Forwarding

Since containers use `network_mode: none`, Docker's port publishing doesn't work directly. Use a two-hop pattern: host → conlink → container.

**Problem**: Two services both expose port 80, need different host ports.

```yaml
x-network:
  links:
    # forward: maps conlink internal port to container port
    - {service: frontend, bridge: net1, ip: "10.0.1.1/24", forward: ["3080:80/tcp"]}
    - {service: backend, bridge: net1, ip: "10.0.1.2/24", forward: ["3081:80/tcp"]}

services:
  conlink:
    # ports: maps host port to conlink internal port
    ports:
      - "8080:3080"   # host:8080 → conlink:3080 → frontend:80
      - "8081:3081"   # host:8081 → conlink:3081 → backend:80

  frontend:
    image: nginx
    network_mode: none

  backend:
    image: nginx
    network_mode: none
```

**Traffic flow**: `curl localhost:8080` → conlink container port 3080 → forwarded to frontend container port 80.

**Tip**: When container ports are unique, you can use matching internal ports for simplicity:

```yaml
x-network:
  links:
    - {service: api, bridge: net1, forward: ["9090:9090/tcp"]}
    - {service: web, bridge: net1, forward: ["3000:3000/tcp"]}

services:
  conlink:
    ports:
      - "9090:9090"  # Direct mapping when ports don't conflict
      - "3000:3000"
```

## Scaled Services

Auto-incrementing IPs and MACs:

```yaml
services:
  worker:
    image: myapp
    scale: 5

x-network:
  links:
    - service: worker
      bridge: cluster
      ip: 10.0.1.1/24      # becomes .1, .2, .3, .4, .5
      mac: 00:0a:0b:0c:0d:01  # increments last octet
```

## VLAN Configuration

Direct VLAN on host interface:

```yaml
x-network:
  links:
    - service: node
      type: vlan
      outer-dev: enp0s3
      vlanid: 100
      ip: 192.168.100.10/24
```

MacVLAN for external network access:

```yaml
x-network:
  links:
    - service: node
      type: macvlan
      outer-dev: eth0
      mode: bridge
      ip: 192.168.1.50/24
```

## Remote Tunnels

Connect to remote host via Geneve:

```yaml
x-network:
  links:
    - {service: node, bridge: overlay, ip: "10.100.0.1/24"}
  tunnels:
    - type: geneve
      bridge: overlay
      remote: 203.0.113.10
      vni: 1001
```

VXLAN with network emulation:

```yaml
x-network:
  tunnels:
    - type: vxlan
      bridge: datacenter
      remote: 10.0.0.100
      vni: 5000
      netem: "delay 5ms"
```

## Bridge Modes

Force specific bridge mode:

```yaml
x-network:
  links:
    - {service: switch1, bridge: fabric, ip: "10.0.1.1/24"}
    - {service: switch2, bridge: fabric, ip: "10.0.1.2/24"}
  bridges:
    - {bridge: fabric, mode: ovs}
```

Patch mode for 2-node bump-in-wire:

```yaml
x-network:
  links:
    - {service: left, bridge: wire, ip: "10.0.0.1/24"}
    - {service: right, bridge: wire, ip: "10.0.0.2/24"}
  bridges:
    - {bridge: wire, mode: patch}
```

## Service-Level x-network

Network configuration can be embedded directly in service definitions for cleaner organization:

```yaml
services:
  tester:
    image: alpine
    network_mode: none
    cap_add: [NET_ADMIN]
    command: /utils/wait -i ctrl -i mgmt -- /sbin/test.sh
    x-network:
      links:
        - {bridge: ctrl, dev: ctrl, ip: "192.168.1.1/24"}
        - {bridge: mgmt, dev: mgmt, ip: "192.168.2.1/24"}

  worker:
    image: myapp
    network_mode: none
    x-network:
      links:
        - {bridge: ctrl, dev: eth0, ip: "192.168.1.10/24"}
```

**Benefits**:
- Network config lives with the service it describes
- Easier to understand per-service networking at a glance
- Works alongside top-level `x-network` (configs are merged)

**Merging behavior**: Service-level links are added to top-level links. If both define the same service+dev combination, service-level wins.

## Interface Bonding and Redundancy

Dual-homed servers with interfaces across redundant switches for high availability:

```yaml
x-network:
  bridges:
    - {bridge: switch_a_port1, mode: patch}
    - {bridge: switch_a_port2, mode: patch}
    - {bridge: switch_b_port1, mode: patch}
    - {bridge: switch_b_port2, mode: patch}
    - {bridge: switch_peer1, mode: patch}
    - {bridge: switch_peer2, mode: patch}

  links:
    # Switch A connections
    - {service: switch_a, bridge: ctrl, dev: eth0, ip: "192.168.1.10/24"}
    - {service: switch_a, bridge: switch_peer1, dev: eth49}
    - {service: switch_a, bridge: switch_peer2, dev: eth50}
    - {service: switch_a, bridge: switch_a_port1, dev: eth1}
    - {service: switch_a, bridge: switch_a_port2, dev: eth2}

    # Switch B connections
    - {service: switch_b, bridge: ctrl, dev: eth0, ip: "192.168.1.11/24"}
    - {service: switch_b, bridge: switch_peer1, dev: eth49}
    - {service: switch_b, bridge: switch_peer2, dev: eth50}
    - {service: switch_b, bridge: switch_b_port1, dev: eth1}
    - {service: switch_b, bridge: switch_b_port2, dev: eth2}

    # Server 1: dual-homed across both switches
    - {service: server1, bridge: switch_a_port1, dev: eth0, mac: "02:01:0A:00:00:01"}
    - {service: server1, bridge: switch_b_port1, dev: eth1, mac: "02:01:0B:00:00:01"}

    # Server 2: dual-homed across both switches
    - {service: server2, bridge: switch_a_port2, dev: eth0, mac: "02:02:0A:00:00:01"}
    - {service: server2, bridge: switch_b_port2, dev: eth1, mac: "02:02:0B:00:00:01"}

services:
  server1:
    image: myserver
    network_mode: none
    cap_add: [NET_ADMIN]
    # Wait for both interfaces, then create bond
    command: /utils/wait -i eth0 -i eth1 -- /sbin/init.sh bond0 eth0 eth1
```

**Key pattern**: Each server has two interfaces (eth0, eth1) connected to different switches. The container's init script bonds them for redundancy.

## MAC Address Conventions

Use systematic MAC address schemes to encode topology information for easier debugging:

**Recommended format**: `02:XX:YY:ZZ:ZZ:ZZ`
- First octet `02` = locally administered (won't conflict with real hardware)
- Encode meaningful information in remaining octets

**Example scheme for switch-server topology**:

| Component | MAC Pattern | Example | Meaning |
|-----------|-------------|---------|---------|
| Switch A port N | `02:AA:NN:00:00:NN` | `02:AA:01:00:00:01` | Switch A, port 1 |
| Switch B port N | `02:AB:NN:00:00:NN` | `02:AB:03:00:00:03` | Switch B, port 3 |
| Server N to Switch A | `02:NN:AA:00:00:01` | `02:01:AA:00:00:01` | Server 1 → Switch A |
| Server N to Switch B | `02:NN:AB:00:00:02` | `02:01:AB:00:00:02` | Server 1 → Switch B |

```yaml
x-network:
  links:
    # Switch A port 1 connects to Server 1
    - {service: switch_a, bridge: link_a1, dev: eth1, mac: "02:AA:01:00:00:01"}
    - {service: server1, bridge: link_a1, dev: eth0, mac: "02:01:AA:00:00:01"}

    # Switch B port 1 connects to Server 1
    - {service: switch_b, bridge: link_b1, dev: eth1, mac: "02:AB:01:00:00:01"}
    - {service: server1, bridge: link_b1, dev: eth1, mac: "02:01:AB:00:00:02"}
```

**Debugging benefit**: When you see MAC `02:01:AA:00:00:01` in packet captures or ARP tables, you immediately know it's Server 1's interface to Switch A.

## Complete Compose Example

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

  router:
    image: alpine
    cap_add: [NET_ADMIN]
    command: sh -c 'while ! ip link show eth0 up; do sleep 1; done; sysctl -w net.ipv4.ip_forward=1; sleep infinity'

  client:
    image: alpine
    cap_add: [NET_ADMIN]
    command: sh -c 'while ! ip link show eth0 up; do sleep 1; done; sleep infinity'

  server:
    image: alpine
    cap_add: [NET_ADMIN]
    command: sh -c 'while ! ip link show eth0 up; do sleep 1; done; python3 -m http.server 80'

x-network:
  links:
    - {service: router, bridge: lan, dev: eth0, ip: "10.0.1.1/24"}
    - {service: router, bridge: wan, dev: eth1, ip: "10.0.2.1/24"}
    - {service: client, bridge: lan, ip: "10.0.1.10/24", route: "default via 10.0.1.1"}
    - {service: server, bridge: wan, ip: "10.0.2.10/24", route: "default via 10.0.2.1"}
```

## Async Startup Pattern

Conlink creates interfaces asynchronously. Wait for them:

```yaml
# Using conlink's wait utility
command: /utils/wait -i eth0 -- /utils/wait -I eth0 -- myapp

# Using shell loop
command: sh -c 'while ! ip link show eth0 up; do sleep 1; done; myapp'

# Chain waits
command: /utils/wait -i eth0 -t server:8080 -- client --connect server:8080
```

Wait utility options:
- `-i eth0` - Wait for interface to exist
- `-I eth0` - Wait for interface with IP assigned
- `-t host:port` - Wait for TCP port
- `-f /path` - Wait for file to exist
- `-c "cmd"` - Wait for command to succeed

## Hybrid Docker + Conlink Networking

Sometimes you need both standard Docker networking AND conlink bridges - for example, when running Kubernetes (k3s) where internal cluster DNS requires Docker networking, but external services need conlink access.

**Use case**: k3s cluster where agents need Docker DNS to resolve the server, but external services need conlink bridges to communicate with pods.

```yaml
# Define a standard Docker network for k3s internal communication
networks:
  k3s:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.117.0/24
          gateway: 192.168.117.1

# Conlink bridge for external access
x-network:
  bridges:
    - {bridge: k0, mode: linux}
  links:
    # k3s nodes get conlink interfaces for external access
    - {service: k3s-server,  bridge: k0, dev: eth1, ip: 10.200.0.1/24}
    - {service: k3s-agent-1, bridge: k0, dev: eth1, ip: 10.200.0.2/24}
    - {service: k3s-agent-2, bridge: k0, dev: eth1, ip: 10.200.0.3/24}
    # External services connect via conlink
    - {service: test-client, bridge: k0, dev: eth1, ip: 10.200.0.11/24,
       route: ["10.42.0.0/15 via 10.200.0.2 dev eth1"]}

x-k3s-hosts: &k3s-hosts
  k3s-server:  192.168.117.10
  k3s-agent-1: 192.168.117.11
  k3s-agent-2: 192.168.117.12

services:
  k3s-server:
    image: rancher/k3s:latest
    privileged: true
    # Use Docker network for k3s internal (DNS resolution)
    networks: {k3s: {ipv4_address: 192.168.117.10}}
    extra_hosts: {<<: *k3s-hosts}
    # Conlink adds eth1 for external access
    command: server --disable=traefik

  k3s-agent-1:
    image: rancher/k3s:latest
    privileged: true
    networks: {k3s: {ipv4_address: 192.168.117.11}}
    extra_hosts: {<<: *k3s-hosts}
    environment:
      - K3S_URL=https://k3s-server:6443
    command: agent

  test-client:
    image: curlimages/curl
    network_mode: none  # Conlink only
    command: sleep infinity
```

**Key points**:
- k3s services use `networks:` for Docker networking (internal cluster communication)
- k3s services also get conlink interfaces (eth1) for external access
- External services use `network_mode: none` with conlink only
- Routes on external services direct pod traffic through k3s agents

**When to use hybrid networking**:
- Kubernetes clusters needing external service access
- Services requiring Docker's DNS resolution alongside custom networking
- CI environments where default DNS resolvers have permission issues

## Multiple Routes

Add multiple static routes to a link for complex routing scenarios:

```yaml
x-network:
  links:
    - service: gateway
      bridge: external
      dev: eth0
      ip: 10.200.0.1/24
      route:
        - "10.42.0.0/16 via 10.200.0.2"    # Kubernetes pod network
        - "10.43.0.0/16 via 10.200.0.2"    # Kubernetes service network
        - "172.16.0.0/12 via 10.200.0.3"   # Private network range
        - "default via 10.200.0.254"        # Default gateway
```

**Single route** (string):
```yaml
route: "default via 10.0.1.1"
```

**Multiple routes** (array):
```yaml
route:
  - "10.0.0.0/8 via 10.200.0.1"
  - "192.168.0.0/16 via 10.200.0.2"
```

**Inline array** (compact):
```yaml
route: ["10.42.0.0/15 via 10.200.0.2 dev eth1", "default via 10.200.0.254"]
```

**Common use cases**:
- Routing to Kubernetes pod/service networks through cluster nodes
- Multi-datacenter routing with different gateways per network
- Split routing for VPN-like configurations
- Connecting isolated network segments through specific routers
