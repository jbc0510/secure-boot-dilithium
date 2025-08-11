#!/usr/bin/env bash
set -euo pipefail
LOG="out/fail_run.log"
mkdir -p out
./tools/test_matrix.sh 2>&1 | tee "$LOG"
echo "[LOG SAVED] $LOG"
