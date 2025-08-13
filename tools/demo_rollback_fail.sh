#!/usr/bin/env bash
set -euo pipefail
RED="\033[31m"; YEL="\033[33m"; R="\033[0m"

echo -e "${YEL}[ROLLBACK-FAIL MINI] v0 should be rejected (counter=1)${R}"
make -s rom_mock gen_keys_c sign_fw_c

mkdir -p out
printf '\x01\x00\x00\x00' > out/otp_counter.bin  # floor = 1
head -c 4096 /dev/urandom > out/rb.payload
[ -f out/pubkey.bin ] || ./tools/gen_keys_c out/pubkey.bin out/seckey.bin
./tools/sign_fw_c out/rb.payload out/pubkey.bin out/seckey.bin 0 out/rb.header  # version 0

echo -e "${YEL}Expect: Rollback: version=0 < 1 (fail)${R}"
./rom_mock out/rb.header out/rb.payload out/rb.header out/rb.payload || true
