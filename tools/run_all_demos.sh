#!/usr/bin/env bash
set -euo pipefail
CYN="\033[36m"; YEL="\033[33m"; GRN="\033[32m"; MAG="\033[35m"; BLU="\033[34m"; R="\033[0m"

echo -e "${CYN}==================== ALL DEMOS ====================${R}"
echo -e "${GRN}1) Baseline secure boot:${R} sign once → verify PASS"
echo -e "${YEL}2) A/B fallback + OTP counter:${R} corrupt A → boot B; bump version"
echo -e "${MAG}3) Rollback enforcement:${R} lower version rejected"
echo -e "${BLU}4) Footprint report:${R} sizes, map/stack, runtime timing"
echo -e "${CYN}===================================================${R}"

echo -e "\n${GRN}[1/4] Baseline demo${R}"
./tools/demo_baseline.sh

echo -e "\n${YEL}[2/4] A/B fallback + OTP counter demo${R}"
./tools/demo_ab_counter.sh

echo -e "\n${MAG}[3/4] Rollback-only demo${R}"
./tools/demo_rollback_only.sh || true

echo -e "\n${BLU}[4/4] Footprint measurement${R}"
./tools/measure_footprint.sh
echo -e "${BLU}Report saved to out/footprint_report.txt${R}"
