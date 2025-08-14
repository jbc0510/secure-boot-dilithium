#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

# 1) build signer (if needed)
pushd "$ROOT/sw/golden" >/dev/null
ALG_DIR=./ext/pqclean/crypto_sign/ml-dsa-44/clean
COMMON_DIR=./ext/pqclean/common
gcc -O2 -std=c99 -I"$ALG_DIR" -I"$COMMON_DIR" \
  signer.c randombytes.c \
  $ALG_DIR/*.c $COMMON_DIR/fips202.c \
  -o signer
popd >/dev/null

# 2) make vectors (good + bad)
mkdir -p "$ROOT/build"
echo "hello-secure-boot-dilithium" > "$ROOT/build/firmware.bin"
"$ROOT/sw/golden/signer" genkey "$ROOT/build/pubkey.bin" "$ROOT/build/seckey.bin"
"$ROOT/sw/golden/signer" sign  "$ROOT/build/pubkey.bin" "$ROOT/build/seckey.bin" \
                               "$ROOT/build/firmware.bin" "$ROOT/build/firmware.sig"
cp "$ROOT/build/firmware.bin" "$ROOT/build/firmware_corrupt.bin"
printf '\x00' | dd of="$ROOT/build/firmware_corrupt.bin" bs=1 count=1 seek=0 conv=notrunc

# 3) build verilator sim (if needed)
pushd "$ROOT/sim" >/dev/null
./gen_filelist.sh
ABS_LIB=$(readlink -f "$ROOT/sw/golden/libpqclean_sig.a" || true)
if [ ! -f "$ROOT/sw/golden/libpqclean_sig.a" ]; then
  # minimal static lib for dpi (verify paths may differ in your tree)
  echo "Rebuilding libpqclean_sig.a"
  pushd "$ROOT/sw/golden" >/dev/null
  ALG_DIR=./ext/pqclean/crypto_sign/ml-dsa-44/clean
  COMMON_DIR=./ext/pqclean/common
  rm -f libpqclean_sig.a *.o
  gcc -O2 -std=c99 -I"$ALG_DIR" -I"$COMMON_DIR" -c $ALG_DIR/*.c $COMMON_DIR/fips202.c
  ar rcs libpqclean_sig.a *.o
  rm -f *.o
  popd >/dev/null
  ABS_LIB=$(readlink -f "$ROOT/sw/golden/libpqclean_sig.a")
fi

verilator -Wall --timing -cc -f filelist.f \
  -CFLAGS "-O2 -std=gnu++17 -I$ROOT/sw/golden" \
  --top-module tb_sb_top_axil \
  --exe sim_main.cpp $ROOT/sw/golden/dpi_golden_dilithium.cc \
  "$ABS_LIB" $ROOT/sw/golden/randombytes_pqclean.c

make -C obj_dir -f Vtb_sb_top_axil.mk Vtb_sb_top_axil
popd >/dev/null

# 4) run demo (good -> PASS, bad -> FAIL)
echo "=== GOLDEN: expected PASS ==="
"$ROOT/sim/obj_dir/Vtb_sb_top_axil" \
  +FW="$ROOT/build/firmware.bin" \
  +SIG="$ROOT/build/firmware.sig" \
  +PK="$ROOT/build/pubkey.bin"

echo "=== GOLDEN: expected FAIL ==="
"$ROOT/sim/obj_dir/Vtb_sb_top_axil" \
  +FW="$ROOT/build/firmware_corrupt.bin" \
  +SIG="$ROOT/build/firmware.sig" \
  +PK="$ROOT/build/pubkey.bin"
