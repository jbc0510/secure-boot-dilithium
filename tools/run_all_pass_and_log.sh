#!/usr/bin/env bash
set -euo pipefail
LOG="out/pass_run.log"
mkdir -p out
./tools/test_all_pass.sh 2>&1 | tee "$LOG"
echo "[LOG SAVED] $LOG"
