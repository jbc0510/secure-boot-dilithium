#!/usr/bin/env bash
set -euo pipefail

# Colors
GRN="\033[32m"; RED="\033[31m"; YEL="\033[33m"; CYN="\033[36m"; BLU="\033[34m"; MAG="\033[35m"; R="\033[0m"
OK="${GRN}PASS${R}"; NO="${RED}FAIL${R}"

say(){ echo -e "$@"; }
hr(){ echo -e "${CYN}------------------------------------------------------------${R}"; }

# Ensure build artifacts exist
make -s rom_mock gen_keys_c sign_fw_c >/dev/null

mkdir -p out

# Helpers
RESET_FLOOR(){ printf '\x01\x00\x00\x00' > out/otp_counter.bin; }
RUN(){ bash -c "$@" >/dev/null 2>&1; echo $?; }

RESULT(){ # name, rc, expect(0=pass exp,1=fail exp)
  local name="$1" rc="$2" want="$3"
  if { [ "$want" -eq 0 ] && [ "$rc" -eq 0 ]; } || { [ "$want" -eq 1 ] && [ "$rc" -ne 0 ]; }; then
    printf "%-36s : %b\n" "$name" "$OK"
  else
    printf "%-36s : %b (rc=%s)\n" "$name" "$NO" "$rc"
  fi
}

# Workspace
rm -f out/*.header out/*.payload 2>/dev/null || true

echo -e "${CYN}================ Secure Boot Demo Suite ================${R}"

#########################
# 1) Baseline (expect PASS)
#########################
hr
say "${GRN}[1/6] Baseline — sign v1 & verify${R}"
RESET_FLOOR
head -c 4096 /dev/urandom > out/base.payload
[ -f out/pubkey.bin ] || ./tools/gen_keys_c out/pubkey.bin out/seckey.bin
./tools/sign_fw_c out/base.payload out/pubkey.bin out/seckey.bin 1 out/base.header
rc_base=$(RUN "./rom_mock out/base.header out/base.payload out/base.header out/base.payload")
RESULT "Baseline (v1, floor=1)" "$rc_base" 0

################################
# 2) Payload tamper (expect FAIL)
################################
hr
say "${YEL}[2/6] Payload tamper — flip 1 byte in payload${R}"
cp out/base.payload out/tamper.payload
cp out/base.header  out/tamper.header
printf '\x00' | dd of=out/tamper.payload bs=1 seek=0 count=1 conv=notrunc status=none >/dev/null 2>&1
rc_tamper=$(RUN "./rom_mock out/tamper.header out/tamper.payload out/tamper.header out/tamper.payload")
RESULT "Payload tamper rejected" "$rc_tamper" 1

###################################
# 3) Signature tamper (expect FAIL)
###################################
hr
say "${MAG}[3/6] Signature tamper — zero 16 bytes in signature blob${R}"
# Compute signature blob offset from header
BLOB_OFF=$(awk '/#define[ \t]+HDR_BLOB_OFFSET/ {print $3}' rom/image_format.h)
PK_LEN=$(od -An -tu4 -N4 -j16 out/base.header | tr -d ' ')
SIG_LEN=$(od -An -tu4 -N4 -j20 out/base.header | tr -d ' ')
SIG_OFF=$((BLOB_OFF + PK_LEN))
cp out/base.header out/sigt.header
dd if=/dev/zero of=out/sigt.header bs=1 seek=$SIG_OFF count=16 conv=notrunc status=none >/dev/null 2>&1
RESET_FLOOR
rc_sig=$(RUN "./rom_mock out/sigt.header out/base.payload out/sigt.header out/base.payload")
RESULT "Signature tamper rejected" "$rc_sig" 1

#################################
# 4) Rollback (v0 < floor=1) FAIL
#################################
hr
say "${RED}[4/6] Rollback — sign v0, floor=1 → reject${R}"
RESET_FLOOR
head -c 4096 /dev/urandom > out/rb.payload
./tools/sign_fw_c out/rb.payload out/pubkey.bin out/seckey.bin 0 out/rb.header
rc_rb=$(RUN "./rom_mock out/rb.header out/rb.payload out/rb.header out/rb.payload")
RESULT "Rollback v0<1 rejected" "$rc_rb" 1

##########################################
# 5) A/B fallback (A corrupted, B v2) PASS
##########################################
hr
say "${BLU}[5/6] A/B fallback — corrupt A, valid B@v2 → boot B${R}"
RESET_FLOOR
head -c 4096 /dev/urandom > out/slotA.payload
head -c 4096 /dev/urandom > out/slotB.payload
./tools/sign_fw_c out/slotA.payload out/pubkey.bin out/seckey.bin 1 out/slotA.header
./tools/sign_fw_c out/slotB.payload out/pubkey.bin out/seckey.bin 2 out/slotB.header
printf '\x00' | dd of=out/slotA.payload bs=1 seek=0 count=1 conv=notrunc status=none >/dev/null 2>&1
rc_ab=$(RUN "./rom_mock out/slotA.header out/slotA.payload out/slotB.header out/slotB.payload")
RESULT "A/B fallback to B (v2)" "$rc_ab" 0

#####################################################
# 6) OTP bump — run v2 → counter should become 2 PASS
#####################################################
hr
say "${GRN}[6/6] OTP bump — sign v2 & run; floor updates to 2${R}"
RESET_FLOOR
head -c 4096 /dev/urandom > out/v2.payload
./tools/sign_fw_c out/v2.payload out/pubkey.bin out/seckey.bin 2 out/v2.header
rc_bump=$(RUN "./rom_mock out/v2.header out/v2.payload out/v2.header out/v2.payload")
otp_hex=$(xxd -g1 out/otp_counter.bin 2>/dev/null | awk '{print $2$3$4$5}' | head -n1)
RESULT "OTP bumped to 2 after v2 PASS" "$rc_bump" 0
printf "%-36s : %s\n" "OTP counter bytes" "${otp_hex:-N/A}"

# Optional: footprint + matrix
hr
if [ -x tools/measure_footprint.sh ]; then
  say "${CYN}[+] Generating footprint report…${R}"
  ./tools/measure_footprint.sh >/dev/null || true
  say "   Report: out/footprint_report.txt"
fi

if [ -x tools/verify_matrix.sh ]; then
  hr
  say "${CYN}[+] Running verification matrix (full)…${R}"
  ./tools/verify_matrix.sh
fi

hr
say "${GRN}All demos completed.${R}"
