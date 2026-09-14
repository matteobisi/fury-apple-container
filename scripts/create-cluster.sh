#!/usr/bin/env bash
set -euo pipefail

# Override these only when the host has sufficient resources for the local profile.
CLUSTER_NAME="${CLUSTER_NAME:-sighup-local}"
CLUSTER_CPUS="${CLUSTER_CPUS:-6}"
CLUSTER_MEMORY="${CLUSTER_MEMORY:-16g}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$ROOT_DIR/.state/${CLUSTER_NAME}.kubeconfig}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

require_command container
require_command kubectl

if container inspect "$CLUSTER_NAME" >/dev/null 2>&1; then
  printf 'Apple Container cluster already exists: %s\nRun destroy-cluster.sh before creating a fresh lab.\n' "$CLUSTER_NAME" >&2
  exit 1
fi

mkdir -p "$(dirname "$KUBECONFIG_PATH")"
container k8s create \
  --name "$CLUSTER_NAME" \
  --cpus "$CLUSTER_CPUS" \
  --memory "$CLUSTER_MEMORY"

# Keep the lab context separate from the user's selected default kubeconfig context.
container k8s write-config --name "$CLUSTER_NAME" --kubeconfig "$KUBECONFIG_PATH"
kubectl --kubeconfig "$KUBECONFIG_PATH" config use-context "$CLUSTER_NAME"
kubectl --kubeconfig "$KUBECONFIG_PATH" wait \
  --for=condition=Ready "node/${CLUSTER_NAME}" \
  --timeout=240s

printf 'Cluster %s is ready.\n' "$CLUSTER_NAME"
printf 'Use: export KUBECONFIG=%q\n' "$KUBECONFIG_PATH"
