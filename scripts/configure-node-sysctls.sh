#!/usr/bin/env bash
set -euo pipefail

# These values are the SIGHUP on-premises recommendation for Fluent Bit tailing.
CLUSTER_NAME="${CLUSTER_NAME:-sighup-local}"
INOTIFY_MAX_USER_INSTANCES="${INOTIFY_MAX_USER_INSTANCES:-8192}"
INOTIFY_MAX_USER_WATCHES="${INOTIFY_MAX_USER_WATCHES:-524288}"

if ! container inspect "$CLUSTER_NAME" >/dev/null 2>&1; then
  printf 'Apple Container cluster not found: %s\n' "$CLUSTER_NAME" >&2
  exit 1
fi

# Pass each value as an argument instead of interpolating it into a command shell.
if [[ ! "$INOTIFY_MAX_USER_INSTANCES" =~ ^[1-9][0-9]*$ ||
  ! "$INOTIFY_MAX_USER_WATCHES" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Inotify limits must be positive integers.\n' >&2
  exit 1
fi

container exec "$CLUSTER_NAME" sysctl -w \
  "fs.inotify.max_user_instances=${INOTIFY_MAX_USER_INSTANCES}"
container exec "$CLUSTER_NAME" sysctl -w \
  "fs.inotify.max_user_watches=${INOTIFY_MAX_USER_WATCHES}"
# Print the effective values because node settings are intentionally applied at runtime.
container exec "$CLUSTER_NAME" sysctl \
  fs.inotify.max_user_instances fs.inotify.max_user_watches
