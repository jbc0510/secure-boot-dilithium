#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DIR="${1:?usage: tools/sign_folder.sh <dir> [glob_pattern]}"
PATTERN="${2:-*}"

# Keys + ROM fresh once
[ -f out/pub.key ] || ./tools/gen_keys_c out/pub.key out/sec.key
make -s regen
mkdir -p out

# Collect files
mapfile -t FILES < <(find "$DIR" -type f -name "$PATTERN" -print | sort)
[ "${#FILES[@]}" -gt 0 ] || { echo "no files matched"; exit 0; }

echo "signing ${#FILES[@]} files from: $DIR (pattern: $PATTERN)"
i=0
for f in "${FILES[@]}"; do
  i=$((i+1))
  echo "[$i/${#FILES[@]}] $f"
  ./tools/sign_file.sh "$f" >/dev/null
done

# Refresh CSV if jq exists
if command -v jq >/dev/null 2>&1; then
  grep -E '^\s*\{.*\}\s*$' out/sign_runs.jsonl \
    | jq -r '[.ts,.file,.version,.sizes.payload,.sizes.header,.sizes.package,.times.sign,.times.verify,.result] | @csv' \
    > out/sign_runs.csv
  echo "wrote out/sign_runs.csv"
fi

echo "done."
