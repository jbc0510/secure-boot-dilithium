#!/usr/bin/env bash
set -euo pipefail
if [ $# -ne 2 ]; then
  echo "Usage: $0 <old> <new>" >&2
  exit 2
fi
A="$1"; B="$2"
echo "=== DIFF: $A  ->  $B"
echo "-- sizes"
stat -c '%n %s bytes' "$A" "$B" 2>/dev/null || stat -f '%N %z bytes' "$A" "$B"
echo "-- sha256"
sha256sum "$A" "$B" 2>/dev/null || (shasum -a 256 "$A"; shasum -a 256 "$B")
echo "-- first 64 bytes (hex)"
xxd -g1 -l 64 "$A" | sed 's/^/OLD /'
xxd -g1 -l 64 "$B" | sed 's/^/NEW /'
echo "-- byte positions changed (cmp)"
cmp -l "$A" "$B" | head -50 || true
echo
