# Dilithium Secure Boot — Demo Walkthrough

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
./rom_mock -v out/h_clean out/p_clean out/h_clean out/p_clean

2. Wrong-Key FAIL → Rotate OTP → PASS

./tools/gen_keys_c out/alt_pub.key out/alt_sec.key
./tools/sign_fw_c out/p_clean out/alt_pub.key out/alt_sec.key 2 out/h_wrong
./rom_mock out/h_wrong out/p_clean out/h_wrong out/p_clean   # FAIL

./tools/gen_otp_header.sh out/alt_pub.key
make rom_mock
./rom_mock -v out/h_wrong out/p_clean out/h_wrong out/p_clean   # PASS
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


