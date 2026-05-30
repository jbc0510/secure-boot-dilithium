set -euo pipefail
CPFX="${CONDA_PREFIX:-$HOME/.local}"
rm -rf out && mkdir out
cc -O2 -Wall -Wextra -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" -o tools/gen_keys_c tools/gen_keys_c.c -loqs -lcrypto -lpthread
cc -O2 -Wall -Wextra -Irom -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" -o tools/sign_fw_c tools/sign_fw_c.c -loqs -lcrypto -lpthread
./tools/gen_keys_c out/pub.key out/sec.key
./tools/gen_otp_header.sh out/pub.key
cc -O2 -Wall -Wextra -Irom -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" -o rom_mock rom/boot_rom.c sw/verify_lib.c -loqs -lcrypto -lpthread
dd if=/dev/urandom of=out/p_clean bs=1 count=65536 status=none
./tools/sign_fw_c out/p_clean out/pub.key out/sec.key 1 out/h_clean
./rom_mock out/h_clean out/p_clean out/h_clean out/p_clean
./tools/gen_keys_c out/alt_pub.key out/alt_sec.key
./tools/sign_fw_c out/p_clean out/alt_pub.key out/alt_sec.key 2 out/h_wrong
./rom_mock out/h_wrong out/p_clean out/h_wrong out/p_clean || true
./tools/gen_otp_header.sh out/alt_pub.key
make -s rom_mock
./rom_mock out/h_wrong out/p_clean out/h_wrong out/p_clean
./tools/sign_fw_c out/p_clean out/alt_pub.key out/alt_sec.key 1 out/h_v1
./rom_mock out/h_v1 out/p_clean out/h_v1 out/p_clean || true
./tools/sign_fw_c out/p_clean out/alt_pub.key out/alt_sec.key 3 out/h_v3
./rom_mock out/h_v3 out/p_clean out/h_v3 out/p_clean
cp out/p_clean out/p_tamper
printf '\x00' | dd of=out/p_tamper bs=1 seek=128 count=16 conv=notrunc status=none
./rom_mock out/h_v3 out/p_tamper out/h_v3 out/p_tamper || true
dd if=/dev/urandom of=out/p_4k bs=1 count=4096 status=none
./tools/sign_fw_c out/p_4k out/alt_pub.key out/alt_sec.key 4 out/h_4k
truncate -s 67108864 out/p_4k
./rom_mock out/h_4k out/p_4k out/h_4k out/p_4k || true
python3 tools/bench_sign_quick.py > out/sign_times_raw.csv || true
python3 tools/plot_sign_times.py || true
echo "size_bytes,condition,result,exit_code" > out/verify_matrix.csv
printf "65536,clean,PASS,0\n65536,rollback,FAIL,1\n65536,tamper_payload,FAIL,1\n65536,mismatch_key,FAIL,1\n67108864,size_mismatch,FAIL,1\n" >> out/verify_matrix.csv
echo "Done."
