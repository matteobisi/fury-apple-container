#!/usr/bin/env bash
set -euo pipefail

FURYCTL_VERSION="${FURYCTL_VERSION:-0.35.1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${FURYCTL_INSTALL_DIR:-$ROOT_DIR/.tools/furyctl}"
ARCHIVE="furyctl-darwin-arm64.tar.gz"
RELEASE_URL="https://github.com/sighupio/furyctl/releases/download/v${FURYCTL_VERSION}"
CHECKSUMS_FILE="${TMPDIR:-/tmp}/furyctl-${FURYCTL_VERSION}-checksums.txt"
ARCHIVE_FILE="${TMPDIR:-/tmp}/${ARCHIVE}"
trap 'rm -f "$CHECKSUMS_FILE" "$ARCHIVE_FILE"' EXIT

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  printf 'This helper installs the macOS arm64 Furyctl release only.\n' >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
curl --fail --silent --show-error --location \
  "$RELEASE_URL/checksums.txt" \
  -o "$CHECKSUMS_FILE"
curl --fail --silent --show-error --location \
  "$RELEASE_URL/$ARCHIVE" \
  -o "$ARCHIVE_FILE"

expected_checksum="$(awk -v archive="$ARCHIVE" '$2 == archive { print $1 }' "$CHECKSUMS_FILE")"
actual_checksum="$(shasum -a 256 "$ARCHIVE_FILE" | awk '{ print $1 }')"
if [[ -z "$expected_checksum" || "$expected_checksum" != "$actual_checksum" ]]; then
  printf 'Checksum verification failed for %s.\n' "$ARCHIVE" >&2
  exit 1
fi

tar -xzf "$ARCHIVE_FILE" -C "$INSTALL_DIR"
"$INSTALL_DIR/furyctl" version
