#!/bin/sh
set -eu

ROLE=$1; shift

# Point CRI’s default CNI paths at where k3s actually puts them
mkdir -p /opt/cni /etc/cni
ln -sfn /var/lib/rancher/k3s/data/cni                 /opt/cni/bin
ln -sfn /var/lib/rancher/k3s/agent/etc/cni/net.d      /etc/cni/net.d

mkdir -p /var/lib/rancher/k3s/agent/etc/containerd/
cat > /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl <<EOF
[plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc.options]
  SystemdCgroup = false

[plugins."io.containerd.cri.v1.runtime".cni]
  bin_dir  = "/var/lib/rancher/k3s/data/cni"
  conf_dir = "/var/lib/rancher/k3s/agent/etc/cni/net.d"
EOF

K3S_ARGS=""
# Common kubelet arguments to fix cgroup issues
# NOTE: still has periodic "Failed to kill all the processes attached to cgroup" log message
K3S_ARGS="${K3S_ARGS} --kubelet-arg=cgroup-driver=cgroupfs"
K3S_ARGS="${K3S_ARGS} --kubelet-arg=feature-gates=KubeletInUserNamespace=true"
K3S_ARGS="${K3S_ARGS} --kubelet-arg=fail-swap-on=false"
K3S_ARGS="${K3S_ARGS} --kubelet-arg=cgroup-root=/"
K3S_ARGS="${K3S_ARGS} --kubelet-arg=runtime-cgroups=/systemd/system.slice"
K3S_ARGS="${K3S_ARGS} --kubelet-arg=kubelet-cgroups=/systemd/system.slice"

echo exec k3s "${ROLE}" ${K3S_ARGS} "$@"
exec k3s "${ROLE}" ${K3S_ARGS} "$@"

