#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

INPUT="${1:?usage: tools/sign_file.sh <file> [version]}"
VERSION="${2:-}"

mkdir -p out

bytes() { stat -c%s "$1"; }
label() { numfmt --to=iec --suffix=B "$1"; }

# Ensure keys + OTP header + ROM
[ -f out/pub.key ] || ./tools/gen_keys_c out/pub.key out/sec.key
./tools/gen_otp_header.sh out/pub.key
make -s rom_mock

# Choose version: next OTP if not supplied (do NOT reset OTP)
if [ -z "$VERSION" ]; then
  VMIN=0
  if [ -f out/otp_counter.bin ]; then
    VMIN="$(od -An -tu4 out/otp_counter.bin 2>/dev/null | tr -d ' ' || echo 0)"
  fi
  VERSION=$((VMIN + 1))
fi

# Stage payload
cp -f -- "$INPUT" out/firmware.payload

# Sizes before
PAYLOAD_SIZE="$(bytes out/firmware.payload)"
PAYLOAD_LABEL="$(label "$PAYLOAD_SIZE")"
HEADER_PATH="out/firmware.header"
PAYLOAD_PATH="out/firmware.payload"

# Time sign
RAW_SIGN=$({ /usr/bin/time -f "%e" \
  ./tools/sign_fw_c "$PAYLOAD_PATH" out/pub.key out/sec.key "$VERSION" "$HEADER_PATH" \
  >/dev/null; } 2>&1)
SIGN_TIME="$(printf "%.5f" "$RAW_SIGN")"

# Sizes after
HEADER_SIZE="$(bytes "$HEADER_PATH")"
HEADER_LABEL="$(label "$HEADER_SIZE")"
PACKAGE_SIZE=$((PAYLOAD_SIZE + HEADER_SIZE))
PACKAGE_LABEL="$(label "$PACKAGE_SIZE")"
GROWTH_BYTES=$((PACKAGE_SIZE - PAYLOAD_SIZE))
GROWTH_LABEL="$(label "$GROWTH_BYTES")"
GROWTH_PCT="$(awk -v g="$GROWTH_BYTES" -v p="$PAYLOAD_SIZE" 'BEGIN{if(p==0){print "0.00"} else printf("%.2f",(g/p)*100)}')"

# Verify
set +e
RAW_VERIFY=$({ /usr/bin/time -f "%e" \
  ./rom_mock "$HEADER_PATH" "$PAYLOAD_PATH" "$HEADER_PATH" "$PAYLOAD_PATH" \
  >/dev/null; } 2>&1)
RC=$?
set -e
VERIFY_TIME="$(printf "%.5f" "$RAW_VERIFY")"
VERIFY_RESULT="PASS"; [ $RC -ne 0 ] && VERIFY_RESULT="FAIL"

# Report
cat <<REPORT

================ Secure Signing Report ================
Input file        : $INPUT
Version           : $VERSION
Payload size      : ${PAYLOAD_SIZE} bytes (${PAYLOAD_LABEL})
Header size       : ${HEADER_SIZE} bytes (${HEADER_LABEL})
Package size      : ${PACKAGE_SIZE} bytes (${PACKAGE_LABEL})
Overhead          : ${GROWTH_BYTES} bytes (${GROWTH_LABEL})  (${GROWTH_PCT}%)
Sign time (s)     : ${SIGN_TIME}
Verify time (s)   : ${VERIFY_TIME}
Verify result     : ${VERIFY_RESULT}
Header path       : ${HEADER_PATH}
Payload path      : ${PAYLOAD_PATH}
=======================================================
REPORT

# --- JSON log (one line per run) ---
TS="$(date -Iseconds 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")"
jq -nc \
  --arg ts "$TS" \
  --arg file "$INPUT" \
  --arg ver "$VERSION" \
  --arg result "$VERIFY_RESULT" \
  --arg sign "$SIGN_TIME" \
  --arg verify "$VERIFY_TIME" \
  --arg header_path "$HEADER_PATH" \
  --arg payload_path "$PAYLOAD_PATH" \
  --argjson payload "$PAYLOAD_SIZE" \
  --argjson header "$HEADER_SIZE" \
  --argjson package "$PACKAGE_SIZE" \
'{
  ts: $ts,
  file: $file,
  version: $ver,
  sizes: { payload: $payload, header: $header, package: $package },
  times: { sign: ($sign|tonumber), verify: ($verify|tonumber) },
  result: $result,
  paths: { header: $header_path, payload: $payload_path }
}' >> out/sign_runs.jsonl
