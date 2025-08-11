#!/usr/bin/env bash
set -euo pipefail
RED="\033[31m"; GRN="\033[32m"; YEL="\033[33m"; R="\033[0m"
pause(){ secs="$1"; while [ "$secs" -gt 0 ]; do printf "\r${YEL}... continuing in %2ds${R}" "$secs"; sleep 1; secs=$((secs-1)); done; echo; }

echo -e "${YEL}[DEMO] A/B fallback + monotonic OTP counter${R}"
make -s rom_mock gen_keys_c sign_fw_c

echo -e "${YEL}[1/4] Reset state${R}"
mkdir -p out
printf '\x01\x00\x00\x00' > out/otp_counter.bin
head -c 4096 /dev/urandom > out/slotA.payload
head -c 4096 /dev/urandom > out/slotB.payload
[ -f out/pubkey.bin ] || ./tools/gen_keys_c out/pubkey.bin out/seckey.bin
pause 20

echo -e "${YEL}[2/4] Sign images: A=v1, B=v2${R}"
./tools/sign_fw_c out/slotA.payload out/pubkey.bin out/seckey.bin 1 out/slotA.header
./tools/sign_fw_c out/slotB.payload out/pubkey.bin out/seckey.bin 2 out/slotB.header
pause 20

echo -e "${YEL}[3/4] Run 1: expect A boots (counter stays 1)${R}"
./rom_mock out/slotA.header out/slotA.payload out/slotB.header out/slotB.payload
xxd -g1 out/otp_counter.bin
pause 20

echo -e "${YEL}[4/4] Corrupt A → fallback to B; counter bumps to 2${R}"
printf '\x00' | dd of=out/slotA.payload bs=1 seek=0 count=1 conv=notrunc status=none
./rom_mock out/slotA.header out/slotA.payload out/slotB.header out/slotB.payload
xxd -g1 out/otp_counter.bin
echo -e "${GRN}[DONE] Demo complete.${R}"
