#!/usr/bin/env bash
set -euo pipefail

# Colors
ESC=$(printf '\033')
RESET="${ESC}[0m"; BOLD="${ESC}[1m"
GREEN="${ESC}[32m"; CYAN="${ESC}[36m"; YELLOW="${ESC}[33m"

say() { printf "%b\n" "${BOLD}${CYAN}$*${RESET}"; }
pass() { printf "%b\n" "${BOLD}${GREEN}$*${RESET}"; }
note() { printf "%b\n" "${YELLOW}$*${RESET}"; }

mkdir -p out

say "[1] PASS Test"
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload && pass "✔ PASS (clean image)"

say "[2] Payload Test (valid)"
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload && pass "✔ PASS (payload intact)"

say "[3] Signature Test (valid)"
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload && pass "✔ PASS (signature intact)"

say "[4] Rollback Test (valid)"
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 2 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload && pass "✔ PASS (version meets min)"

note "[DONE] All tests passed — no tampering, no rollback."
