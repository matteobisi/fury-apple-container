#!/usr/bin/env bash
set -euo pipefail

# Set CLUSTER_NAME when deleting a separately named lab cluster.
CLUSTER_NAME="${CLUSTER_NAME:-sighup-local}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/.state/${CLUSTER_NAME}.kubeconfig}"

# This removes the Container-managed Kubernetes node and only this lab's isolated kubeconfig.
container k8s delete --name "$CLUSTER_NAME"
rm -f "$KUBECONFIG_PATH"
printf 'Deleted Apple Container cluster %s.\n' "$CLUSTER_NAME"
