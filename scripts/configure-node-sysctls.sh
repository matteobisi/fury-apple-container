#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-sighup-local}"
INOTIFY_MAX_USER_INSTANCES="${INOTIFY_MAX_USER_INSTANCES:-8192}"
INOTIFY_MAX_USER_WATCHES="${INOTIFY_MAX_USER_WATCHES:-524288}"

if ! container inspect "$CLUSTER_NAME" >/dev/null 2>&1; then
  printf 'Apple Container cluster not found: %s\n' "$CLUSTER_NAME" >&2
  exit 1
fi

container exec "$CLUSTER_NAME" /bin/sh -ec "
  sysctl -w fs.inotify.max_user_instances=${INOTIFY_MAX_USER_INSTANCES}
  sysctl -w fs.inotify.max_user_watches=${INOTIFY_MAX_USER_WATCHES}
  sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
"
