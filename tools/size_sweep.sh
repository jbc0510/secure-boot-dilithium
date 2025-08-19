#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SIZES=(1K 4K 16K 64K 256K 1M 4M 16M 32M 64M)

mkdir -p out
: > out/size_sweep.csv
echo "size_bytes,size_label,sign_sec,verify_sec,result" >> out/size_sweep.csv

command -v /usr/bin/time >/dev/null || { echo "need /usr/bin/time"; exit 1; }

# Ensure keys and ROM are ready
[ -f out/pub.key ] || ./tools/gen_keys_c out/pub.key out/sec.key
./tools/gen_otp_header.sh out/pub.key
make -s rom_mock

# Reset OTP counter
printf '\x00\x00\x00\x00' > out/otp_counter.bin

ver=0
for s in "${SIZES[@]}"; do
  case "$s" in
    *K) bytes=$(( ${s%K} * 1024 ));;
    *M) bytes=$(( ${s%M} * 1024 * 1024 ));;
    *)  bytes=$s;;
  esac

  # Create payload of exact size fast (fallocate) or fallback to dd
  if command -v fallocate >/dev/null; then
    fallocate -l "$bytes" out/firmware.payload
  else
    dd if=/dev/zero of=out/firmware.payload bs="$bytes" count=1 status=none
  fi

  ver=$((ver+1))

  # Time sign
  raw_sign=$({ /usr/bin/time -f "%e" \
    ./tools/sign_fw_c out/firmware.payload out/pub.key out/sec.key "$ver" out/firmware.header \
    >/dev/null; } 2>&1)
  t_sign=$(printf "%.5f" "$raw_sign")

  # Time verify
  set +e
  raw_verify=$({ /usr/bin/time -f "%e" \
    ./rom_mock out/firmware.header out/firmware.payload out/firmware.header out/firmware.payload \
    >/dev/null; } 2>&1)
  rc=$?
  set -e
  t_verify=$(printf "%.5f" "$raw_verify")

  result="PASS"; [ $rc -ne 0 ] && result="FAIL"

  printf "%s,%s,%s,%s,%s\n" "$bytes" "$s" "${t_sign:-NA}" "${t_verify:-NA}" "$result" \
    | tee -a out/size_sweep.csv
done

echo "wrote out/size_sweep.csv"
column -s, -t out/size_sweep.csv
