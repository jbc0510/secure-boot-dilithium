# Dilithium Secure Boot 
# Dilithium Secure Boot — Demo Walkthrough

Minimal, repeatable flow for onboarding and demos. Commands are copy-paste ready. Explanations are short and literal.

## Prereqs

- `liboqs` and OpenSSL available to the compiler.
- Headers and libs on one of these paths:
  - `$CONDA_PREFIX/include` and `$CONDA_PREFIX/lib`, or
  - `$HOME/.local/include` and `$HOME/.local/lib`
- Tools use this interface:
  - `gen_keys_c <pub_out> <sec_out>`
  - `sign_fw_c <payload> <pub.key> <sec.key> <version> <header_out>`
  - `rom_mock <hdrA> <fwA> <hdrB> <fwB>`  (no `-v`)

---

## 0) Fresh demo environment (new folder each time)

Why: keep your main repo clean and make every run reproducible.

```bash
cd ~/projects
TS=$(date +%Y%m%d_%H%M%S)
cp -r secure-boot-dilithium secure-boot-dilithium-demo-$TS
cd secure-boot-dilithium-demo-$TS

# liboqs prefix for compiler flags
CPFX="${CONDA_PREFIX:-$HOME/.local}"

# clean outputs
rm -rf out && mkdir out

# build tools explicitly with oqs paths
cc -O2 -Wall -Wextra -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" \
  -o tools/gen_keys_c tools/gen_keys_c.c -loqs -lcrypto -lpthread

cc -O2 -Wall -Wextra -Irom -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" \
  -o tools/sign_fw_c tools/sign_fw_c.c -loqs -lcrypto -lpthread

# keys and OTP header (trusted pubkey compiled into ROM)
./tools/gen_keys_c out/pub.key out/sec.key
./tools/gen_otp_header.sh out/pub.key

# build ROM mock after otp_pk.h exists
cc -O2 -Wall -Wextra -Irom -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" \
  -o rom_mock rom/boot_rom.c sw/verify_lib.c -loqs -lcrypto -lpthread



— Demo Walkthrough

This section shows how to spin up a *fresh clean demo* and run through all verification cases.

---

## 0. Fresh Environment

cd ~/projects

TS=$(date +%Y%m%d_%H%M%S)
cp -r secure-boot-dilithium secure-boot-dilithium-demo-$TS
cd secure-boot-dilithium-demo-$TS
rm -rf out && mkdir out
./tools/gen_keys_c out/pub.key out/sec.key
./tools/gen_otp_header.sh out/pub.key
make clean && make rom_mock
1. Clean PASS

dd if=/dev/urandom of=out/p_clean bs=1 count=65536 status=none
./tools/sign_fw_c out/p_clean out/pub.key out/sec.key 1 out/h_clean
./rom_mock out/h_clean out/p_clean out/h_clean out/p_clean

2. Wrong-Key FAIL → Rotate OTP → PASS

./tools/gen_keys_c out/alt_pub.key out/alt_sec.key
./tools/sign_fw_c out/p_clean out/alt_pub.key out/alt_sec.key 2 out/h_wrong
./rom_mock out/h_wrong out/p_clean out/h_wrong out/p_clean   # FAIL

./tools/gen_otp_header.sh out/alt_pub.key
make rom_mock
./rom_mock out/h_wrong out/p_clean out/h_wrong out/p_clean   # PASS
3. Rollback Protection


./tools/sign_fw_c out/p_clean out/alt_pub.key out/alt_sec.key 1 out/h_v1
./rom_mock out/h_v1 out/p_clean out/h_v1 out/p_clean         # FAIL

./tools/sign_fw_c out/p_clean out/alt_pub.key out/alt_sec.key 3 out/h_v3
./rom_mock  out/h_v3 out/p_clean out/h_v3 out/p_clean         # PASS
4. Tamper Detection

cp out/p_clean out/p_tamper
dd if=/dev/urandom of=out/p_tamper bs=1 count=16 conv=notrunc seek=128 status=none
./rom_mock out/h_v3 out/p_tamper out/h_v3 out/p_tamper       # FAIL
5. Size Mismatch

dd if=/dev/urandom of=out/p_4k bs=1 count=4096 status=none
./tools/sign_fw_c out/p_4k out/alt_pub.key out/alt_sec.key 4 out/h_4k
truncate -s 67108864 out/p_4k
./rom_mock out/h_4k out/p_4k out/h_4k out/p_4k               # FAIL
6. Benchmark & Charts

./tools/bench_sign_quick.py
python3 tools/plot_sign_times.py
xdg-open out/plot_mean_time.png
xdg-open out/plot_throughput.png
7. Reset OTP to Original Key

./tools/gen_otp_header.sh out/pub.key
make rom_mock
Notes

Always create demos in a new secure-boot-dilithium-demo-<timestamp> folder to keep the repo clean.

When swapping OTP keys, rebuild only the ROM with make rom_mock — do not run make all, or it will overwrite with out/pub.key.


