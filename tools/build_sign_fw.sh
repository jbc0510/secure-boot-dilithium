#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Output directory
mkdir -p out

# Compiler flags (adjust if your system installs oqs/openssl differently)
CC=${CC:-cc}
CFLAGS="-I$CONDA_PREFIX/include -O2 -Wall -Wextra"
LDFLAGS="-L$CONDA_PREFIX/lib -loqs -lcrypto -lpthread"

# Build sign_fw_c
echo "[*] Building tools/sign_fw_c ..."
$CC $CFLAGS \
  tools/sign_fw_c.c \
  -o tools/sign_fw_c \
  $LDFLAGS

echo "[+] Built tools/sign_fw_c"
