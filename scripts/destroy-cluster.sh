#!/usr/bin/env bash
set -euo pipefail

# Set CLUSTER_NAME when deleting a separately named lab cluster.
CLUSTER_NAME="${CLUSTER_NAME:-sighup-local}"

# This removes the Container-managed Kubernetes node, not the local .state kubeconfig.
container k8s delete --name "$CLUSTER_NAME"
printf 'Deleted Apple Container cluster %s.\n' "$CLUSTER_NAME"
