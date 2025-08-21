#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p out
printf '\x00\x00\x00\x00' > out/otp_counter.bin
dd if=/dev/urandom of=out/firmware.payload bs=4096 count=1
./tools/gen_keys_c out/pub.key out/sec.key
./tools/gen_otp_header.sh out/pub.key
make -s rom_mock
./tools/sign_fw_c out/firmware.payload out/pub.key out/sec.key 1 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload out/firmware.header out/firmware.payload
