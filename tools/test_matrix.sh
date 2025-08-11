#!/usr/bin/env bash
set -euo pipefail

# Colors
ESC=$(printf '\033')
RESET="${ESC}[0m"; BOLD="${ESC}[1m"
RED="${ESC}[31m"; GREEN="${ESC}[32m"; CYAN="${ESC}[36m"; YELLOW="${ESC}[33m"

say() { printf "%b\n" "${BOLD}${CYAN}$*${RESET}"; }
pass() { printf "%b\n" "${BOLD}${GREEN}$*${RESET}"; }
fail() { printf "%b\n" "${BOLD}${RED}$*${RESET}"; }
note() { printf "%b\n" "${YELLOW}$*${RESET}"; }

run_verify() {
  local hdr="$1" fw="$2"
  local out
  out="$(./rom_mock "$hdr" "$fw" 2>&1 | tee /dev/tty)"
  echo "$out" | grep -q "VERIFY PASS" && return 0 || return 1
}

mkdir -p out

say "[1] PASS Test (clean image)"
if run_verify out/firmware.header out/firmware.payload; then
  pass "✔ PASS as expected"
else
  fail "✘ Unexpected FAIL (clean image)"; exit 1
fi

say "[2] Payload Tamper Test (expect FAIL)"
cp out/firmware.payload out/firmware.payload.bak
printf '\x00' | dd of=out/firmware.payload bs=1 seek=0 count=1 conv=notrunc status=none
if run_verify out/firmware.header out/firmware.payload; then
  fail "✘ Should have FAILED after payload tamper"
else
  pass "✔ FAIL observed (digest changed → signature mismatch)"
fi
mv out/firmware.payload.bak out/firmware.payload

say "[3] Signature Tamper Test (expect FAIL)"
cp out/firmware.header out/firmware.header.bak
# Calculate signature offset: sig_off = 0x18 + pk_len (LE uint32 at offset 16)
pk_len=$(dd if=out/firmware.header bs=1 skip=16 count=4 status=none 2>/dev/null | od -An -tu4)
sig_off=$((0x18 + pk_len))
printf '\xFF' | dd of=out/firmware.header bs=1 seek=${sig_off} count=1 conv=notrunc status=none
if run_verify out/firmware.header out/firmware.payload; then
  fail "✘ Should have FAILED after signature tamper"
else
  pass "✔ FAIL observed (signature byte flipped)"
fi
mv out/firmware.header.bak out/firmware.header

say "[4] Rollback Test (expect FAIL: version < OTP min)"
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 0 out/firmware.header
if run_verify out/firmware.header out/firmware.payload; then
  fail "✘ Should have FAILED due to rollback"
else
  pass "✔ FAIL observed (version=0 < 1)"
fi

note "[DONE] Matrix complete: 1 PASS, 3 expected FAILs."
