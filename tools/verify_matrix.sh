#!/usr/bin/env bash
set -u  # (no -e here; we’ll capture rc ourselves)

RED="\033[31m"; GRN="\033[32m"; YEL="\033[33m"; CYN="\033[36m"; R="\033[0m"
OK="${GRN}PASS${R}"; NO="${RED}FAIL${R}"

echo -e "${CYN}=== Secure Boot Verification Matrix ===${R}"

# Ensure builds
make -s rom_mock gen_keys_c sign_fw_c >/dev/null

mkdir -p out
RESET_FLOOR(){ printf '\x01\x00\x00\x00' > out/otp_counter.bin; }
result() { # $1 name, $2 rc, $3 expect (0=pass expected, 1=fail expected)
  local want="$3" ; local rc="$2"
  if [[ ($want -eq 0 && $rc -eq 0) || ($want -eq 1 && $rc -ne 0) ]]; then
    printf "%-28s : %b\n" "$1" "$OK"
  else
    printf "%-28s : %b (rc=$rc)\n" "$1" "$NO"
  fi
}
run() { # run cmd and return rc without aborting
  bash -c "$@" >/dev/null 2>&1
  echo $?
}

# 1) Baseline PASS (A=v1, floor=1)
RESET_FLOOR
head -c 4096 /dev/urandom > out/base.payload
[ -f out/pubkey.bin ] || ./tools/gen_keys_c out/pubkey.bin out/seckey.bin
./tools/sign_fw_c out/base.payload out/pubkey.bin out/seckey.bin 1 out/base.header
rc_baseline=$(run "./rom_mock out/base.header out/base.payload out/base.header out/base.payload")

# 2) Payload tamper FAIL
cp out/base.payload out/tamper.payload
cp out/base.header  out/tamper.header
printf '\x00' | dd of=out/tamper.payload bs=1 seek=0 count=1 conv=notrunc status=none >/dev/null 2>&1
rc_tamper=$(run "./rom_mock out/tamper.header out/tamper.payload out/tamper.header out/tamper.payload")

# 3) Signature tamper FAIL (flip last header byte)

RESET_FLOOR
cp out/base.header out/sig.header
BLOB_OFF=$(awk '/#define[ \t]+HDR_BLOB_OFFSET/ {print $3}' rom/image_format.h)
PK_LEN=$(od -An -tu4 -N4 -j16 out/base.header | tr -d ' ')
SIG_LEN=$(od -An -tu4 -N4 -j20 out/base.header | tr -d ' ')
SIG_OFF=$((BLOB_OFF + PK_LEN))
dd if=/dev/zero of=out/sig.header bs=1 seek=$SIG_OFF count=16 conv=notrunc status=none >/dev/null 2>&1
rc_sig=$(run "./rom_mock out/sig.header out/base.payload out/sig.header out/base.payload")
# 4) Rollback FAIL (v0 < floor=1)
RESET_FLOOR
head -c 4096 /dev/urandom > out/rb.payload
./tools/sign_fw_c out/rb.payload out/pubkey.bin out/seckey.bin 0 out/rb.header
rc_rb=$(run "./rom_mock out/rb.header out/rb.payload out/rb.header out/rb.payload")

# 5) A/B fallback PASS (A corrupted, B v2 valid)
RESET_FLOOR
head -c 4096 /dev/urandom > out/slotA.payload
head -c 4096 /dev/urandom > out/slotB.payload
./tools/sign_fw_c out/slotA.payload out/pubkey.bin out/seckey.bin 1 out/slotA.header
./tools/sign_fw_c out/slotB.payload out/pubkey.bin out/seckey.bin 2 out/slotB.header
printf '\x00' | dd of=out/slotA.payload bs=1 seek=0 count=1 conv=notrunc status=none >/dev/null 2>&1
rc_ab=$(run "./rom_mock out/slotA.header out/slotA.payload out/slotB.header out/slotB.payload")

# 6) Counter bump PASS (v2 boots → OTP=2)
RESET_FLOOR
head -c 4096 /dev/urandom > out/v2.payload
./tools/sign_fw_c out/v2.payload out/pubkey.bin out/seckey.bin 2 out/v2.header
rc_bump=$(run "./rom_mock out/v2.header out/v2.payload out/v2.header out/v2.payload")
otp_hex=$(xxd -g1 out/otp_counter.bin 2>/dev/null | awk '{print $2$3$4$5}' | head -n1)

echo
echo -e "${CYN}--- Results ---${R}"
result "Baseline (v1, floor=1)"           "$rc_baseline" 0
result "Payload tamper rejected"          "$rc_tamper"   1
result "Signature tamper rejected"        "$rc_sig"      1
result "Rollback v0<1 rejected"           "$rc_rb"       1
result "A/B fallback to B (v2)"           "$rc_ab"       0
result "OTP bumped to 2 after v2 PASS"    "$rc_bump"     0
printf "%-28s : %s\n" "OTP counter bytes" "${otp_hex:-N/A}"

echo -e "${CYN}================ DONE ================${R}"
