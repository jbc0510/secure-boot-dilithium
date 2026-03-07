# Demo Run (Secure Boot + Dilithium)
## Fresh copy
cd ~/projects; TS=$(date +%Y%m%d_%H%M%S); cp -r secure-boot-dilithium secure-boot-dilithium-demo-$TS; cd secure-boot-dilithium-demo-$TS
export CPFX="${CONDA_PREFIX:-$HOME/.local}"; rm -rf out && mkdir -p out
cc -O2 -Wall -Wextra -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" -o tools/gen_keys_c tools/gen_keys_c.c -loqs -lcrypto -lpthread
cc -O2 -Wall -Wextra -Irom -Isw -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" -o tools/sign_fw_c tools/sign_fw_c.c -loqs -lcrypto -lpthread
./tools/gen_keys_c out/pub.key out/sec.key && ./tools/gen_otp_header.sh out/pub.key
cc -O2 -Wall -Wextra -Irom -Isw -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" -o rom_mock rom/boot_rom.c sw/verify_lib.c -loqs -lcrypto -lpthread
dd if=/dev/urandom of=out/p_clean bs=1 count=65536 status=none
./tools/sign_fw_c out/p_clean out/pub.key out/sec.key 1 out/h_clean
./rom_mock out/h_clean out/p_clean out/h_clean out/p_clean
./tools/test_matrix.sh | tee out/verify_matrix.log
python3 tools/bench_sign_quick.py --out out/sign_times.csv
python3 tools/plot_sign_times.py --in out/sign_times.csv --out out/sign_times_plot.png
