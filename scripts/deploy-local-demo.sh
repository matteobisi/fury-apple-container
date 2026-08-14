#!/usr/bin/env bash
set -euo pipefail

# The fully qualified name must match both the imported CRI image and the workload manifest.
CLUSTER_NAME="${CLUSTER_NAME:-sighup-local}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${KUBECONFIG:-$ROOT_DIR/.state/${CLUSTER_NAME}.kubeconfig}}"
IMAGE_NAME="docker.io/library/apple-container-local-demo:0.1.0"

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  printf 'Kubeconfig not found: %s\nRun bootstrap-cluster.sh first or set KUBECONFIG_PATH.\n' "$KUBECONFIG_PATH" >&2
  exit 1
fi

# Build in Apple's local image store, then import into the node's containerd k8s.io namespace.
container build --tag "$IMAGE_NAME" --file "$ROOT_DIR/demo/Containerfile" "$ROOT_DIR/demo"
container k8s load-image --name "$CLUSTER_NAME" "$IMAGE_NAME"
# The manifest uses imagePullPolicy: Never, so this deploy never contacts a registry.
kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f "$ROOT_DIR/manifests/local-demo.yaml"
kubectl --kubeconfig "$KUBECONFIG_PATH" -n local-demo rollout status \
  deployment/local-demo --timeout=180s
kubectl --kubeconfig "$KUBECONFIG_PATH" -n local-demo get pods,service
printf 'Run: kubectl --kubeconfig %q -n local-demo port-forward service/local-demo 8080:80\n' "$KUBECONFIG_PATH"
