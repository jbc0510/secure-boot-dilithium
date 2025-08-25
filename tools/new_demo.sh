#!/usr/bin/env bash
set -euo pipefail
BASE=secure-boot-dilithium
TS=$(date +%Y%m%d_%H%M%S)
DEST=${BASE}-demo-$TS
CPFX="${CONDA_PREFIX:-$HOME/.local}"
cd ~/projects; cp -r "$BASE" "$DEST"; cd "$DEST"
rm -rf out && mkdir out
cc -O2 -Wall -Wextra -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" -o tools/gen_keys_c tools/gen_keys_c.c -loqs -lcrypto -lpthread
cc -O2 -Wall -Wextra -Irom -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" -o tools/sign_fw_c tools/sign_fw_c.c -loqs -lcrypto -lpthread
./tools/gen_keys_c out/pub.key out/sec.key
./tools/gen_otp_header.sh out/pub.key
cc -O2 -Wall -Wextra -Irom -I"$CPFX/include" -L"$CPFX/lib" -Wl,-rpath,"$CPFX/lib" -o rom_mock rom/boot_rom.c sw/verify_lib.c -loqs -lcrypto -lpthread
echo "Demo at $(pwd)"
