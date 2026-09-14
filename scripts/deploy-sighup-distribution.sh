#!/usr/bin/env bash
set -euo pipefail

# KUBECONFIG_PATH takes precedence so the local lab does not alter another project context.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${KUBECONFIG:-$ROOT_DIR/.state/sighup-local.kubeconfig}}"
FURYCTL_BIN="${FURYCTL_BIN:-furyctl}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/furyctl}"

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  printf 'Kubeconfig not found: %s\nRun create-cluster.sh first or set KUBECONFIG_PATH.\n' "$KUBECONFIG_PATH" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  printf 'Required command not found: kubectl\n' >&2
  exit 1
fi

if ! command -v "$FURYCTL_BIN" >/dev/null 2>&1 && [[ ! -x "$FURYCTL_BIN" ]]; then
  printf 'furyctl was not found: %s\nSet FURYCTL_BIN to the downloaded binary.\n' "$FURYCTL_BIN" >&2
  exit 1
fi

# Furyctl reads the target cluster from the profile's {env://KUBECONFIG} reference.
export KUBECONFIG="$KUBECONFIG_PATH"
"$FURYCTL_BIN" apply --config "$ROOT_DIR/furyctl/sighup-local.yaml" --outdir "$OUT_DIR"

# Furyctl renders logging separately, after custom patches have been evaluated.
# Remove the systemd-only tailers that cannot run in the Apple Container node.
kubectl --kubeconfig "$KUBECONFIG_PATH" -n logging delete daemonset \
  systemd-common-host-tailer systemd-etcd-host-tailer --ignore-not-found

kubectl --kubeconfig "$KUBECONFIG_PATH" wait \
  --for=condition=Available deployment --all --all-namespaces --timeout=600s

wait_for_rollouts() {
  local resource="$1"
  local namespace
  local name

  while IFS=$'\t' read -r namespace name; do
    [[ -n "$namespace" && -n "$name" ]] || continue
    kubectl --kubeconfig "$KUBECONFIG_PATH" rollout status \
      "${resource}/${name}" --namespace "$namespace" --timeout=600s
  done < <(
    kubectl --kubeconfig "$KUBECONFIG_PATH" get "$resource" --all-namespaces \
      -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}'
  )
}

wait_for_rollouts daemonset
wait_for_rollouts statefulset
