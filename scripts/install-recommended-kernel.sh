#!/usr/bin/env bash
set -euo pipefail

if ! command -v container >/dev/null 2>&1; then
  printf 'Required command not found: container\n' >&2
  exit 1
fi

# This is explicit because --force intentionally replaces a selected default kernel.
container system kernel set --recommended --force
