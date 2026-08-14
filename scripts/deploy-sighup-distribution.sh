#!/usr/bin/env bash
set -euo pipefail

# KUBECONFIG_PATH takes precedence so the local lab does not alter another project context.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-${KUBECONFIG:-$ROOT_DIR/.state/sighup-local.kubeconfig}}"
FURYCTL_BIN="${FURYCTL_BIN:-furyctl}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/furyctl}"

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  printf 'Kubeconfig not found: %s\nRun bootstrap-cluster.sh first or set KUBECONFIG_PATH.\n' "$KUBECONFIG_PATH" >&2
  exit 1
fi

if ! command -v "$FURYCTL_BIN" >/dev/null 2>&1 && [[ ! -x "$FURYCTL_BIN" ]]; then
  printf 'furyctl was not found: %s\nSet FURYCTL_BIN to the downloaded binary.\n' "$FURYCTL_BIN" >&2
  exit 1
fi

# Furyctl reads the target cluster from the profile's {env://KUBECONFIG} reference.
export KUBECONFIG="$KUBECONFIG_PATH"
"$FURYCTL_BIN" apply --config "$ROOT_DIR/furyctl/sighup-local.yaml" --outdir "$OUT_DIR"
