#!/usr/bin/env bash
set -euo pipefail
MAG="\033[35m"; YEL="\033[33m"; R="\033[0m"
echo -e "${MAG}[ROLLBACK DEMO]${R} Show version floor rejection"
make -s rom_mock gen_keys_c sign_fw_c
mkdir -p out
printf '\x01\x00\x00\x00' > out/otp_counter.bin
head -c 4096 /dev/urandom > out/slotA.payload
head -c 4096 /dev/urandom > out/slotB.payload
[ -f out/pubkey.bin ] || ./tools/gen_keys_c out/pubkey.bin out/seckey.bin
./tools/sign_fw_c out/slotA.payload out/pubkey.bin out/seckey.bin 1 out/slotA.header
./tools/sign_fw_c out/slotB.payload out/pubkey.bin out/seckey.bin 0 out/slotB.header
echo -e "${YEL}We’ll corrupt Slot A to force fallback; expect: rollback fail on B (v0<1)${R}"
printf '\x00' | dd of=out/slotA.payload bs=1 seek=0 count=1 conv=notrunc status=none
./rom_mock out/slotA.header out/slotA.payload out/slotB.header out/slotB.payload
