#!/usr/bin/env bash
set -euo pipefail
PUB=${1:-out/pub.key}
OUT=rom/otp_pk.h
[ -f "$PUB" ] || { echo "missing $PUB"; exit 1; }
HASH=$(openssl sha256 -binary "$PUB" | hexdump -v -e '1/1 "0x%02x,"')
mkdir -p rom
cat > "$OUT" <<HDR
#pragma once
#include <stdint.h>
/* Auto-generated from $PUB */
static const uint8_t OTP_PK_HASHES[1][32] = { { $HASH } };
HDR
echo "wrote $OUT"
