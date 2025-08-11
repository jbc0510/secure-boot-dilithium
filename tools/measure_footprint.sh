#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="out"
REPORT="$OUT_DIR/footprint_report.txt"
mkdir -p "$OUT_DIR"
: > "$REPORT"

say(){ echo -e "$@" | tee -a "$REPORT"; }

say "=== Secure-Boot Dilithium Footprint Report ==="
date | tee -a "$REPORT"
say ""

# 0) Ensure binaries exist
make -s rom_mock gen_keys_c sign_fw_c >/dev/null

# 1) Binary sizes
say "-> Binary sizes"
{ size -A rom_mock tools/sign_fw_c tools/gen_keys_c 2>/dev/null || true; } | tee -a "$REPORT"
say ""
ls -lh rom_mock tools/sign_fw_c tools/gen_keys_c | tee -a "$REPORT"
say ""

# 2) Linked libs (shared footprint)
say "-> Linked libraries (rom_mock)"
ldd rom_mock | tee -a "$REPORT" || true
say ""
if compgen -G "/usr/local/lib/liboqs.so*" > /dev/null; then
  say "liboqs on disk:"
  ls -lh /usr/local/lib/liboqs.so* | tee -a "$REPORT"
  say ""
fi

# 3) Build with size-focused flags (map + stack usage)
say "-> Size-focused build (map + stack usage)"
make clean >/dev/null
CFLAGS="-Os -ffunction-sections -fdata-sections -fstack-usage" \
LDFLAGS="-Wl,--gc-sections -Wl,-Map=rom_mock.map" \
make -s rom_mock >/dev/null
ls -lh rom_mock rom_mock.map | tee -a "$REPORT"
say ""

# 3a) Max stack frame (from .su files)
MAX_STACK="n/a"
if ls *.su >/dev/null 2>&1; then
  MAX_STACK=$(awk 'BEGIN{m=0} {if($2+0>m)m=$2} END{print m}' *.su)
  say "Estimated max per-function stack usage (bytes): $MAX_STACK"
  mkdir -p "$OUT_DIR/stack"
  mv -f *.su "$OUT_DIR/stack/" 2>/dev/null || true
else
  say "No .su files found (compiler may not support -fstack-usage)."
fi
say ""

# 4) Runtime cost (verification)
say "-> Runtime (verification path)"
A_HDR="out/slotA.header"; A_FW="out/slotA.payload"
B_HDR="out/slotB.header"; B_FW="out/slotB.payload"

# Create working images if missing
if [ ! -f "$A_HDR" ] || [ ! -f "$A_FW" ] || [ ! -f "$B_HDR" ] || [ ! -f "$B_FW" ]; then
  mkdir -p out
  head -c 4096 /dev/urandom > "$A_FW"
  head -c 4096 /dev/urandom > "$B_FW"
  [ -f out/pubkey.bin ] || ./tools/gen_keys_c out/pubkey.bin out/seckey.bin
  ./tools/sign_fw_c "$A_FW" out/pubkey.bin out/seckey.bin 1 "$A_HDR"
  ./tools/sign_fw_c "$B_FW" out/pubkey.bin out/seckey.bin 2 "$B_HDR"
fi

say "Single run timing:"
/usr/bin/time -f "wall=%E user=%U sys=%S" ./rom_mock "$A_HDR" "$A_FW" "$B_HDR" "$B_FW" 2>>"$REPORT" 1>/dev/null || true

say "100x run timing (avg per run shown by division):"
( /usr/bin/time -f "wall=%E user=%U sys=%S" bash -c 'for i in {1..100}; do ./rom_mock out/slotA.header out/slotA.payload out/slotB.header out/slotB.payload >/dev/null; done' ) 2>>"$REPORT" 1>/dev/null || true
say ""

# 5) perf counters (optional)
if command -v perf >/dev/null 2>&1; then
  say "perf stat (5 runs):"
  perf stat -r 5 ./rom_mock "$A_HDR" "$A_FW" "$B_HDR" "$B_FW" 1>/dev/null 2>>"$REPORT" || true
  say ""
fi

# 6) RAM estimate (static buffers used by our code)
# header 4096 + pk 1312 + sig 2420 + digest 64 + pk_hash 32 = 7924 bytes
say "-> Static buffer estimate (our code path)"
say "header(4096) + pk(1312) + sig(2420) + digest(64) + pk_hash(32) = 7924 bytes (~7.7 KiB)"
say "(Note: excludes library/context overhead and I/O buffering.)"
say ""

say "=== Report saved to $REPORT ==="
