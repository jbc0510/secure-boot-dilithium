#!/usr/bin/env python3
import pathlib
import pandas as pd
import matplotlib
matplotlib.use("Agg")  # headless-safe
import matplotlib.pyplot as plt

RAW = pathlib.Path("out/sign_times_raw.csv")
assert RAW.exists(), "Run ./tools/bench_sign_quick.py first."

df = pd.read_csv(RAW)
df["seconds_per_sign"] = pd.to_numeric(df["seconds_per_sign"], errors="coerce")

summary = (
    df.groupby("size_bytes", as_index=False)["seconds_per_sign"]
      .agg(mean_seconds="mean", std_seconds="std", n="count")
      .fillna({"std_seconds": 0.0})
)
summary["size_mib"] = summary["size_bytes"] / (1024 * 1024)
summary["throughput_MBps"] = summary["size_mib"] / summary["mean_seconds"]
summary = summary.sort_values("size_bytes").reset_index(drop=True)

OUT_CSV = pathlib.Path("out/sign_times_summary.csv")
summary.to_csv(OUT_CSV, index=False)

plt.figure()
plt.errorbar(summary["size_mib"], summary["mean_seconds"],
             yerr=summary["std_seconds"], fmt="-o", capsize=4)
plt.xlabel("Payload size (MiB)")
plt.ylabel("Mean sign time (s)")
plt.title("Dilithium signing time vs payload size")
plt.grid(True)
plt.tight_layout()
PLOT_TIME = pathlib.Path("out/plot_mean_time.png")
plt.savefig(PLOT_TIME, dpi=160)
plt.close()

plt.figure()
plt.plot(summary["size_mib"], summary["throughput_MBps"], marker="o")
plt.xlabel("Payload size (MiB)")
plt.ylabel("Throughput (MB/s)")
plt.title("Dilithium signing throughput vs payload size")
plt.grid(True)
plt.tight_layout()
PLOT_THR = pathlib.Path("out/plot_throughput.png")
plt.savefig(PLOT_THR, dpi=160)
plt.close()

print(f"Wrote {OUT_CSV}")
print(f"Wrote {PLOT_TIME}")
print(f"Wrote {PLOT_THR}")
