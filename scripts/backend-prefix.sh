#!/bin/bash
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
case "$1" in "$HMJE_PREFIX_OUTPUT"/*) ;; *) echo 'HMIR input is outside the build output' >&2; exit 2 ;; esac
if [ "$HMJE_PREFIX_SOURCE" != "$HMJE_PREFIX_RELEASE" ]; then
  /usr/bin/swift "$S/map-source-prefix.swift" "$1" "$HMJE_PREFIX_SOURCE" "$HMJE_PREFIX_RELEASE"
fi
exec "$HMJE_PREFIX_BACKEND" "$@"
