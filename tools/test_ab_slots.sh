#!/usr/bin/env bash
set -euo pipefail

echo "=== [A/B Slot Simulation] ==="
echo "[A/B SLOT TEST] Starting..."

# Build tools/rom if missing
make rom_mock gen_keys_c sign_fw_c >/dev/null

mkdir -p out

# 1) Keys (generate if missing)
if [ ! -f out/pubkey.bin ] || [ ! -f out/seckey.bin ]; then
  echo "[1] Generating keys..."
  ./tools/gen_keys_c out/pubkey.bin out/seckey.bin
else
  echo "[1] Keys exist, skipping..."
fi

# 2) Compute SHA-256 of pubkey and format as C array
PK_HASH_HEX=$(sha256sum out/pubkey.bin | awk '{print $1}')
C_ARRAY=$(echo "$PK_HASH_HEX" | sed 's/../0x&,/g' | sed 's/,$//')

#echo "[*] Updating OTP_PK_HASH in rom/boot_rom.c to $PK_HASH_HEX"
#
## 3) Safely replace the OTP_PK_HASH block (works even if multi-line)
#tmpblk="$(mktemp)"
#awk -v newhash="$C_ARRAY" '
#BEGIN {
#  split(newhash, arr, ",");
#  print "static const uint8_t OTP_PK_HASH[32] = {";
#  for (i=1; i<=length(arr); i++) {
#    gsub(/^ +| +$/, "", arr[i]);
#    printf "  %s", arr[i];
#    if (i < length(arr)) printf ",";
#    print "";
#  }
#  print "};"
#}' > "$tmpblk"
#
#awk '
#  BEGIN {in=0}
#  /static const uint8_t OTP_PK_HASH/ {print "__REPLACE__"; in=1; next}
#  in && /\};/ {in=0; next}
#  !in {print}
#' rom/boot_rom.c | sed "/__REPLACE__/{
#  r $tmpblk
#  d
#}" > rom/boot_rom.c.new
#mv rom/boot_rom.c.new rom/boot_rom.c
#rm -f "$tmpblk"
#
## 4) Rebuild with updated OTP
#make clean >/dev/null
make rom_mock gen_keys_c sign_fw_c

# 5) Create slot payloads
echo "[2] Making slot payloads..."
head -c 4096 /dev/urandom > out/slotA.payload
head -c 4096 /dev/urandom > out/slotB.payload

# 6) Sign slots (A: v=1, B: v=2)
echo "[3] Signing slots..."
./tools/sign_fw_c out/slotA.payload out/pubkey.bin out/seckey.bin 1 out/slotA.header
./tools/sign_fw_c out/slotB.payload out/pubkey.bin out/seckey.bin 2 out/slotB.header

# 7) Run: both valid -> expect boot Slot A
echo "[4] Run 1: Both slots valid (expect A boots)"
./rom_mock out/slotA.header out/slotA.payload out/slotB.header out/slotB.payload

# 8) Corrupt Slot A -> expect fallback to B
echo "[5] Run 2: Corrupt Slot A, expect fallback to B"
printf '\x00' | dd of=out/slotA.payload bs=1 seek=0 count=1 conv=notrunc status=none
./rom_mock out/slotA.header out/slotA.payload out/slotB.header out/slotB.payload

echo "[DONE] A/B slot simulation complete."
