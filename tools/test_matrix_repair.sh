#!/bin/bash
set -e
mkdir -p out

echo "[Init] fresh payload + keys + header (v=1)"
dd if=/dev/urandom of=out/firmware.payload bs=1K count=4
./tools/gen_keys_c out/pubkey.bin out/seckey.bin
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload

echo "[Tamper payload] expect FAIL"
cp out/firmware.payload out/firmware.payload.bak
printf '\x00' | dd of=out/firmware.payload bs=1 seek=0 count=1 conv=notrunc
./rom_mock out/firmware.header out/firmware.payload || true

echo "[Repair payload by restoring or re-signing]"
mv out/firmware.payload.bak out/firmware.payload
# Or: re-sign instead of restoring
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload

echo "[Tamper signature] expect FAIL"
cp out/firmware.header out/firmware.header.bak
# Signature begins at 0x18 + pk_len (1312) = 0x560 for Dilithium-2
printf '\xFF' | dd of=out/firmware.header bs=1 seek=$((0x560)) count=1 conv=notrunc
./rom_mock out/firmware.header out/firmware.payload || true

echo "[Repair signature by restoring or re-signing]"
mv out/firmware.header.bak out/firmware.header
# Or: re-sign to regenerate sig
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload

echo "[Rollback (v=0) expect FAIL]"
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 0 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload || true

echo "[Fix rollback: sign with v>=1]"
./tools/sign_fw_c out/firmware.payload out/pubkey.bin out/seckey.bin 1 out/firmware.header
./rom_mock out/firmware.header out/firmware.payload

echo "[DONE] All repaired to PASS."
