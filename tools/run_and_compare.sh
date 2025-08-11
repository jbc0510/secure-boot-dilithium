#!/usr/bin/env bash
set -euo pipefail

mkdir -p out

# 1) Run both flows and capture logs
./tools/run_matrix_and_log.sh
./tools/run_all_pass_and_log.sh

FAIL_LOG="out/fail_run.log"
PASS_LOG="out/pass_run.log"
DIFF_TXT="out/pass_vs_fail.diff"
REPORT_HTML="out/pass_vs_fail_diff.html"

# 2) Produce a unified diff (text)
diff -u "$PASS_LOG" "$FAIL_LOG" > "$DIFF_TXT" || true

# 3) Make an HTML report with simple coloring
#    - strip ANSI from logs
#    - escape < & > for HTML
strip_ansi() { sed -r 's/\x1B\[[0-9;]*[A-Za-z]//g'; }
escape_html() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

PASS_ESC=$(cat "$PASS_LOG" | strip_ansi | escape_html)
FAIL_ESC=$(cat "$FAIL_LOG" | strip_ansi | escape_html)

# Colorize diff lines with minimal styling
diff_to_html() {
  awk '
  BEGIN {
    print "<pre class=\"diff\">"
  }
  {
    gsub(/&/, "\\&amp;"); gsub(/</, "\\&lt;"); gsub(/>/, "\\&gt;");
    if ($0 ~ /^\\+\\+\\+|^---/) { print "<span class=\"head\">" $0 "</span>"; }
    else if ($0 ~ /^@@/)       { print "<span class=\"hunk\">" $0 "</span>"; }
    else if ($0 ~ /^\\+/)      { print "<span class=\"add\">" $0 "</span>";  }
    else if ($0 ~ /^\\-/)      { print "<span class=\"del\">" $0 "</span>";  }
    else                       { print $0; }
  }
  END { print "</pre>" }
  '
}

DIFF_HTML=$(cat "$DIFF_TXT" | diff_to_html)

cat > "$REPORT_HTML" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<title>Secure Boot Dilithium — PASS vs FAIL Report</title>
<style>
  body { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; margin: 24px; line-height: 1.35; }
  h1 { margin: 0 0 16px 0; }
  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
  pre { background:#0e0e10; color:#e6e6e6; padding:12px; border-radius:8px; overflow:auto; max-height:45vh; }
  .diff { background:#0e0e10; }
  .add { color:#b6fcb6; }
  .del { color:#ff9aa2; }
  .hunk { color:#80c7ff; }
  .head { color:#ffd280; }
  .pill { display:inline-block; padding:4px 8px; border-radius:999px; font-weight:600; }
  .ok { background:#0f5132; color:#d1f7df; }
  .bad { background:#5c1a1a; color:#ffd7d7; }
  .meta { color:#aaa; font-size: 0.9em; }
  a { color:#7cc0ff; text-decoration:none; }
</style>
</head>
<body>
<h1>Secure Boot (Dilithium) — PASS vs FAIL</h1>

<p class="meta">
  Generated: $(date)<br/>
  Logs: <a href="pass_run.log">pass_run.log</a> • <a href="fail_run.log">fail_run.log</a> • <a href="pass_vs_fail.diff">pass_vs_fail.diff</a>
</p>

<h2>Run Outputs</h2>
<div class="grid">
  <div>
    <h3>All-PASS Run <span class="pill ok">PASS</span></h3>
    <pre>$PASS_ESC</pre>
  </div>
  <div>
    <h3>Matrix Run <span class="pill bad">Expected FAILs</span></h3>
    <pre>$FAIL_ESC</pre>
  </div>
</div>

<h2>Diff (PASS vs FAIL)</h2>
$DIFF_HTML

</body>
</html>
HTML

echo "[REPORT SAVED] $REPORT_HTML"
