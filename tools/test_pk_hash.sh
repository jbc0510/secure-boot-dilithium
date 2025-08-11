#!/usr/bin/env bash
set -euo pipefail
ESC=$(printf '\033'); RESET="${ESC}[0m"; BOLD="${ESC}[1m"
CYAN="${ESC}[36m"; GREEN="${ESC}[32m"; RED="${ESC}[31m"; YELLOW="${ESC}[33m"
say(){ printf "%b\n" "${BOLD}${CYAN}$*${RESET}"; }
pass(){ printf "%b\n" "${BOLD}${GREEN}$*${RESET}"; }
fail(){ printf "%b\n" "${BOLD}${RED}$*${RESET}"; }
note(){ printf "%b\n" "${YELLOW}$*${RESET}"; }
run_verify(){ ./rom_mock "$1" "$2" >/dev/stdout 2>&1 | tee /dev/tty | grep -q "VERIFY PASS"; }

mkdir -p out

say "[5] PK-hash enforcement"
# Ensure we start from a clean, valid header
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
if run_verify out/firmware.header out/firmware.payload; then
  pass "✔ Baseline PASS"
else
  fail "✘ Unexpected FAIL on baseline"; exit 1
fi

# Tamper public key in header → should hit pk mismatch vs OTP
./tools/gen_keys_c out/other_pubkey.bin out/other_seckey.bin
cp out/firmware.header out/firmware.header.bak
dd if=out/other_pubkey.bin of=out/firmware.header bs=1 seek=$((0x18)) conv=notrunc status=none
if run_verify out/firmware.header out/firmware.payload; then
  fail "✘ Should have FAILED due to PK mismatch"
else
  pass "✔ FAIL observed (pk mismatch vs OTP)"
fi

# Restore header and confirm PASS again
mv out/firmware.header.bak out/firmware.header
if run_verify out/firmware.header out/firmware.payload; then
  pass "✔ Restored PASS"
else
  fail "✘ Unexpected FAIL after restore"; exit 1
fi

note "[DONE] PK-hash enforcement demonstrated."
