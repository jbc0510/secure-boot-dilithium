#!/usr/bin/env bash
set -euo pipefail

mkdir -p out

echo "[Init] fresh payload + keys + header (v=1)"
dd if=/dev/urandom of=out/firmware.payload bs=1K count=4 status=none
./tools/gen_keys_c out/pubkey.bin out/seckey.bin
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload

cp out/firmware.payload out/firmware.payload.clean
cp out/firmware.header  out/firmware.header.clean

echo
echo "=== Case 2: Payload tamper -> EXPECT FAIL"
cp out/firmware.payload out/firmware.payload.tamper
printf '\x00' | dd of=out/firmware.payload.tamper bs=1 seek=0 count=1 conv=notrunc status=none
./tools/diff_hex.sh out/firmware.payload.clean out/firmware.payload.tamper
./rom_mock out/firmware.header out/firmware.payload.tamper || echo "[OK] FAIL observed"
# Repair by restoring clean payload
cp out/firmware.payload.clean out/firmware.payload
./rom_mock out/firmware.header out/firmware.payload

echo
echo "=== Case 3: Signature tamper -> EXPECT FAIL"
# Compute signature offset dynamically:
# header layout: magic(0) hdr_size(4) version(8) fw_size(12) pk_len(16) sig_len(20)
# sig_offset = 0x18 + pk_len
pk_len=$(dd if=out/firmware.header bs=1 skip=4 count=1 status=none 2>/dev/null | od -An -tu4)
sig_off=$(( 0x18 + pk_len ))
cp out/firmware.header out/firmware.header.tamper
printf '\xFF' | dd of=out/firmware.header.tamper bs=1 seek=${sig_off} count=1 conv=notrunc status=none
./tools/diff_hex.sh out/firmware.header.clean out/firmware.header.tamper
./rom_mock out/firmware.header.tamper out/firmware.payload || echo "[OK] FAIL observed"
# Repair by restoring clean header
cp out/firmware.header.clean out/firmware.header
./rom_mock out/firmware.header out/firmware.payload

echo
echo "=== Case 4: Rollback (version 0) -> EXPECT FAIL"
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 0 out/firmware.header
# Show version field delta (offset 0x08)
echo "-- Version field (LE uint32) before/after:"
echo -n "OLD v="; dd if=out/firmware.header.clean bs=1 skip=8 count=4 status=none | od -An -tu4
echo -n "NEW v="; dd if=out/firmware.header       bs=1 skip=8 count=4 status=none | od -An -tu4
./rom_mock out/firmware.header out/firmware.payload || echo "[OK] FAIL observed"

echo
echo "[Repair rollback: re-sign with v=1 -> PASS]"
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload

echo
echo "[DONE] Demonstrated FAILs with printed diffs, then repaired to PASS]"
