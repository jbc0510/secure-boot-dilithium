#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

make -s regen
mkdir -p out

# base valid image
dd if=/dev/zero of=out/firmware.payload bs=4096 count=1 status=none
./tools/sign_fw_c out/firmware.payload out/pub.key out/sec.key 1 out/firmware.header

mut() { cp out/firmware.header "$1"; python3 - "$1" <<'PY'
import sys,random
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
ops=[
  lambda x: x.__setitem__(0,0x00),                          # break magic
  lambda x: x.__setitem__(4,0x00) or x.__setitem__(5,0x00), # shrink header_size
  lambda x: x.__setitem__(12,0xff),                         # version very high
  lambda x: x.extend(b'\x00'),                              # header too long
  lambda x: x.__delitem__(slice(0,1)),                      # header too short
  lambda x: x.__setitem__(32,0xff),                         # pk_len nonsense
  lambda x: x.__setitem__(36,0x00),                         # sig_len zero
  lambda x: x.__setitem__(random.randrange(len(x)), random.randrange(256)), # random flip
]
random.choice(ops)(b)
open(p,'wb').write(b)
PY
}

passes=0; fails=0
for i in $(seq 1 100); do
  H="out/mut_$i.header"
  mut "$H" || true
  if ./rom_mock "$H" out/firmware.payload "$H" out/firmware.payload >/dev/null 2>&1; then
    echo "[$i] unexpected PASS"; fails=$((fails+1))
  else
    echo "[$i] expected FAIL"; passes=$((passes+1))
  fi
done
echo "Mutation summary: expected FAILs=$passes, unexpected PASS=$fails"
