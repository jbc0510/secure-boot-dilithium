#!/usr/bin/env bash
set -euo pipefail
GRN="\033[32m"; YEL="\033[33m"; R="\033[0m"

echo -e "${YEL}[BUMP-TO-2 MINI] v2 should pass and update counter to 2${R}"
make -s rom_mock gen_keys_c sign_fw_c

mkdir -p out
printf '\x01\x00\x00\x00' > out/otp_counter.bin  # start at 1
head -c 4096 /dev/urandom > out/v2.payload
[ -f out/pubkey.bin ] || ./tools/gen_keys_c out/pubkey.bin out/seckey.bin
./tools/sign_fw_c out/v2.payload out/pubkey.bin out/seckey.bin 2 out/v2.header  # version 2

echo -e "${YEL}Run: expect PASS + 'OTP counter updated to 2'${R}"
./rom_mock out/v2.header out/v2.payload out/v2.header out/v2.payload

echo -e "${GRN}Counter after run:${R}"
xxd -g1 out/otp_counter.bin
