#!/usr/bin/env bash
set -euo pipefail

# Override these only when the host has sufficient resources for the local profile.
CLUSTER_NAME="${CLUSTER_NAME:-sighup-local}"
CLUSTER_CPUS="${CLUSTER_CPUS:-6}"
CLUSTER_MEMORY="${CLUSTER_MEMORY:-16g}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/.state/${CLUSTER_NAME}.kubeconfig}"
# Match the kindnet manifest bundled with the verified Container 1.2.2 plugin.
CNI_URL="https://raw.githubusercontent.com/apple/container/1.2.2/Sources/Plugins/K8s/Resources/kindnet.yaml"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

require_command container
require_command kubectl
require_command jq
require_command curl

# Keep this lab's context separate from the user's default kubeconfig.
mkdir -p "$(dirname "$KUBECONFIG_PATH")"

if ! container inspect "$CLUSTER_NAME" >/dev/null 2>&1; then
  # Capture the output so recovery is allowed only for the documented 1.2.2 failure.
  set +e
  create_output="$(
    container k8s create \
      --name "$CLUSTER_NAME" \
      --cpus "$CLUSTER_CPUS" \
      --memory "$CLUSTER_MEMORY" 2>&1
  )"
  create_status=$?
  set -e

  if (( create_status != 0 )); then
    printf '%s\n' "$create_output" >&2
    if ! grep -Fq 'node prep failed' <<<"$create_output"; then
      printf 'Apple Container cluster creation failed before the known 1.2.2 node-preparation issue.\n' >&2
      exit "$create_status"
    fi
  fi
fi

if ! container exec "$CLUSTER_NAME" /bin/sh -c 'test -f /etc/kubernetes/admin.conf'; then
  # Container 1.2.2 calls iptables-nft even when kindest/node selected legacy iptables.
  # This temporary recovery is tracked in apple/container#2120; only use it for that incompatibility.
  if container exec "$CLUSTER_NAME" /bin/sh -c '/usr/sbin/iptables-nft -t mangle -S >/dev/null 2>&1'; then
    printf 'Cluster is uninitialized but the documented Container 1.2.2 iptables-nft failure was not detected.\n' >&2
    exit 1
  fi

  # Apple Container exposes the node address in CIDR notation; kubeadm needs the address only.
  NODE_IP="$(
    container inspect "$CLUSTER_NAME" |
      jq -r '.[0].status.networks[0].ipv4Address | split("/")[0]'
  )"

  # Reproduce only the two TCP MSS rules the failed plugin setup did not install.
  container exec "$CLUSTER_NAME" /bin/sh -c '
    set -eu
    /usr/sbin/iptables-legacy -t mangle -A OUTPUT -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1220
    /usr/sbin/iptables-legacy -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1220
  '

  kubeadm_config="$(
    cat <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${NODE_IP}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.35.5
networking:
  podSubnet: 10.244.0.0/16
apiServer:
  certSANs:
  - 127.0.0.1
  - ${NODE_IP}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
failSwapOn: false
EOF
  )"

  container exec "$CLUSTER_NAME" /bin/sh -c \
    "printf '%s\n' '$kubeadm_config' > /etc/kubernetes/kubeadm-config.yaml"
  container exec "$CLUSTER_NAME" /usr/bin/kubeadm init \
    --config /etc/kubernetes/kubeadm-config.yaml \
    --ignore-preflight-errors Swap,SystemVerification,FileContent--proc-sys-net-bridge-bridge-nf-call-iptables
  container exec "$CLUSTER_NAME" /bin/sh -c \
    'mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config && KUBECONFIG=/etc/kubernetes/admin.conf kubectl taint nodes --all node-role.kubernetes.io/control-plane-'
fi

# Fluent Bit requires higher inotify limits when it watches every node log file.
"$ROOT_DIR/scripts/configure-node-sysctls.sh"
# Write and select an isolated context, then apply the CNI required by manual kubeadm recovery.
container k8s write-config --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG_PATH"
kubectl --kubeconfig "$KUBECONFIG_PATH" config use-context "$CLUSTER_NAME"
curl --fail --silent --show-error --location "$CNI_URL" |
  kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f -
kubectl --kubeconfig "$KUBECONFIG_PATH" wait \
  --for=condition=Ready "node/${CLUSTER_NAME}" \
  --timeout=240s

printf 'Cluster %s is ready.\n' "$CLUSTER_NAME"
printf 'Use: export KUBECONFIG=%q\n' "$KUBECONFIG_PATH"
