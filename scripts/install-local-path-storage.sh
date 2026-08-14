#!/usr/bin/env bash
set -euo pipefail

# KUBECONFIG_PATH takes precedence so the local lab does not alter another project context.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${KUBECONFIG:-$ROOT_DIR/.state/sighup-local.kubeconfig}}"
# Pin the provisioner version used by the verified single-node lab.
LOCAL_PATH_MANIFEST="https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.32/deploy/local-path-storage.yaml"

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  printf 'Kubeconfig not found: %s\nRun bootstrap-cluster.sh first or set KUBECONFIG_PATH.\n' "$KUBECONFIG_PATH" >&2
  exit 1
fi

# Install dynamic local storage, wait for its controller, then make it the default class.
curl --fail --silent --show-error --location "$LOCAL_PATH_MANIFEST" |
  kubectl --kubeconfig "$KUBECONFIG_PATH" apply -f -
kubectl --kubeconfig "$KUBECONFIG_PATH" -n local-path-storage rollout status \
  deployment/local-path-provisioner --timeout=240s
kubectl --kubeconfig "$KUBECONFIG_PATH" patch storageclass local-path --type merge \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl --kubeconfig "$KUBECONFIG_PATH" get storageclass
