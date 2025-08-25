#!/usr/bin/env python3
import csv, pathlib, subprocess, time, random, statistics as stats
import matplotlib.pyplot as plt

OUT = pathlib.Path("out"); OUT.mkdir(exist_ok=True)
PUB, SEC = OUT/"pub.key", OUT/"sec.key"

# Ensure keys
if not (PUB.exists() and SEC.exists()):
    subprocess.run(["./tools/gen_keys_c", str(PUB), str(SEC)], check=True)

# Sizes and loops
SIZES = [4096, 65536, 1048576, 4194304, 8388608, 16777216, 33554432, 67108864, 134217728]
REPS, ITERS = 3, 50

RAW_CSV   = OUT/"sign_times_raw.csv"
SUM_CSV   = OUT/"sign_times_summary.csv"
PLOT_MS   = OUT/"plot_mean_ms.png"
PLOT_MBPS = OUT/"plot_throughput_mb_s.png"

def sign_once(sec, payload, header, size_bytes, version):
    subprocess.run(
        ["./tools/sign_fw_c", str(sec), str(payload), str(header), "--size", str(size_bytes), "--version", str(version)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True
    )

# --- Run benchmark and write raw CSV ---
with RAW_CSV.open("w", newline="") as f:
    w = csv.writer(f); w.writerow(["size_bytes","run","iters","seconds_total","seconds_per_sign"])
    for sz in SIZES:
        pay, hdr = OUT/f"payload_{sz}.bin", OUT/f"hdr_{sz}.bin"
        # warm‑up to create file at sz
        sign_once(SEC, pay, hdr, sz, 1)

        for r in range(1, REPS+1):
            t0 = time.perf_counter_ns()
            for _ in range(ITERS):
                ver = random.randint(2, 10_000_000)
                sign_once(SEC, pay, hdr, sz, ver)
            t1 = time.perf_counter_ns()
            total = (t1 - t0)/1e9
            per   = total / ITERS
            print(f"size={sz} run={r}/{REPS} iters={ITERS} total={total:.3f}s per={per*1e3:.3f}ms")
            w.writerow([sz, r, ITERS, f"{total:.9f}", f"{per:.9f}"])

print(f"Wrote {RAW_CSV}")

# --- Build summary (mean, stdev, throughput) ---
rows = []
with RAW_CSV.open() as f:
    r = csv.DictReader(f)
    by_size = {}
    for row in r:
        s = int(row["size_bytes"])
        by_size.setdefault(s, []).append(float(row["seconds_per_sign"]))

for s in sorted(by_size):
    per_list = by_size[s]
    mean_s   = stats.mean(per_list)
    stdev_s  = stats.pstdev(per_list) if len(per_list) > 1 else 0.0
    mb       = s/1048576.0
    mbps     = mb/mean_s
    rows.append((s, len(per_list), mean_s, stdev_s, mbps))

with SUM_CSV.open("w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["size_bytes","samples","mean_seconds_per_sign","stdev_seconds_per_sign","throughput_MB_per_s"])
    w.writerows(rows)

print(f"Wrote {SUM_CSV}")

# --- Plot 1: Mean time (ms) vs size (MB) ---
sizes_mb = [s/1048576.0 for s,_,m,_,_ in rows]
mean_ms  = [m*1000.0 for _,_,m,_,_ in rows]

plt.figure()
plt.plot(sizes_mb, mean_ms, marker="o")
plt.title("Dilithium signing time vs payload size")
plt.xlabel("Payload size (MB)")
plt.ylabel("Mean time per sign (ms)")
plt.grid(True, which="both")
plt.tight_layout()
plt.savefig(PLOT_MS, dpi=150)
plt.close()

# --- Plot 2: Throughput (MB/s) vs size (MB) ---
thr = [t for *_, t in rows]

plt.figure()
plt.plot(sizes_mb, thr, marker="o")
plt.title("Dilithium signing throughput vs payload size")
plt.xlabel("Payload size (MB)")
plt.ylabel("Throughput (MB/s)")
plt.grid(True, which="both")
plt.tight_layout()
plt.savefig(PLOT_MBPS, dpi=150)
plt.close()

print(f"Wrote {PLOT_MS}")
print(f"Wrote {PLOT_MBPS}")
