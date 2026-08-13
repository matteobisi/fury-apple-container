#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-sighup-local}"

container k8s delete --name "$CLUSTER_NAME"
printf 'Deleted Apple Container cluster %s.\n' "$CLUSTER_NAME"
