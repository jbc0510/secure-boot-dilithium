#!/usr/bin/env python3
import csv, os, pathlib, subprocess, time, random, sys
OUT = pathlib.Path("out"); OUT.mkdir(exist_ok=True)
PUB, SEC = OUT/"pub.key", OUT/"sec.key"
if not (PUB.exists() and SEC.exists()):
    subprocess.run(["./tools/gen_keys_c", str(PUB), str(SEC)], check=True)

SIZES = [4096, 65536, 1048576, 4194304, 8388608, 16777216, 33554432, 67108864, 134217728]   # 4 KiB, 64 KiB, 1 MiB, 4 MiB
REPS, ITERS = 3, 50                        # faster: 3 reps × 50 signs
CSV = OUT/"sign_times_raw.csv"

with CSV.open("w", newline="") as f:
    w = csv.writer(f); w.writerow(["size_bytes","run","iters","seconds_total","seconds_per_sign"])
    for sz in SIZES:
        pay, hdr = OUT/f"payload_{sz}.bin", OUT/f"hdr_{sz}.bin"
        with pay.open("wb") as fp: fp.write(os.urandom(sz))
        for r in range(1, REPS+1):
            subprocess.run(["./tools/sign_fw_c", str(pay), str(PUB), str(SEC), "1", str(hdr)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            t0 = time.perf_counter_ns()
            for _ in range(ITERS):
                ver = random.randint(1, 10_000_000)
                subprocess.run(["./tools/sign_fw_c", str(pay), str(PUB), str(SEC), str(ver), str(hdr)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            t1 = time.perf_counter_ns()
            total = (t1 - t0)/1e9; per = total/ITERS
            print(f"size={sz} run={r}/{REPS} iters={ITERS} total={total:.3f}s per={per*1e3:.3f}ms")
            w.writerow([sz, r, ITERS, f"{total:.9f}", f"{per:.9f}"])
print(f"Wrote {CSV}")
