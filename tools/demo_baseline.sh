#!/usr/bin/env bash
set -euo pipefail
GRN="\033[32m"; YEL="\033[33m"; R="\033[0m"
echo -e "${GRN}[BASELINE DEMO]${R} Build + sign + verify (PASS)"
make -s rom_mock gen_keys_c sign_fw_c
mkdir -p out
printf '\x01\x00\x00\x00' > out/otp_counter.bin
head -c 4096 /dev/urandom > out/base.payload
[ -f out/pubkey.bin ] || ./tools/gen_keys_c out/pubkey.bin out/seckey.bin
./tools/sign_fw_c out/base.payload out/pubkey.bin out/seckey.bin 1 out/base.header
echo -e "${YEL}Expect: VERIFY PASS${R}"
./rom_mock out/base.header out/base.payload out/base.header out/base.payload
