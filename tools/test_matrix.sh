#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

HDR=out/firmware.header
FW=out/firmware.bin
PUB=out/pub.key
SEC=out/sec.key

# Ensure tools/ROM exist
make -s sign_fw_c gen_keys_c rom_mock >/dev/null

mkdir -p out

# Fresh keys if missing
[ -f "$PUB" ] || ./tools/gen_keys_c "$PUB" "$SEC"

# Fresh OTP header bound to current pubkey
./tools/gen_otp_header.sh "$PUB"
make -s rom_mock >/dev/null

# Helper: sign payload at version V
sign_at_ver() {
  local v="$1"
  ./tools/sign_fw_c "$FW" "$PUB" "$SEC" "$v" "$HDR" >/dev/null
}

# Test 1: clean image (OTP=1, ver=1) -> PASS
printf '\x01\x00\x00\x00' > out/otp_counter.bin
dd if=/dev/urandom of="$FW" bs=4096 count=1 status=none
sign_at_ver 1
if ./rom_mock "$HDR" "$FW" "$HDR" "$FW" >/dev/null; then
  echo "[1] PASS Test (clean image)"
else
  echo "[1] FAIL Test (clean image)"; exit 1
fi

# Test 2: rollback (OTP=10, ver=1) -> FAIL
printf '\x0a\x00\x00\x00' > out/otp_counter.bin
sign_at_ver 1
if ./rom_mock "$HDR" "$FW" "$HDR" "$FW" >/dev/null; then
  echo "✘ Unexpected PASS (rollback)"; exit 1
else
  echo "[2] Expected FAIL (rollback)"
fi

# Test 3: bump (OTP=10, ver=11) -> PASS and OTP should advance
printf '\x0a\x00\x00\x00' > out/otp_counter.bin
sign_at_ver 11
if ./rom_mock "$HDR" "$FW" "$HDR" "$FW" >/dev/null; then
  echo "[3] PASS Test (bump to 11)"
else
  echo "✘ FAIL (bump to 11)"; exit 1
fi
