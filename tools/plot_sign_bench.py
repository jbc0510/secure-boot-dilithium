import pathlib, pandas as pd, matplotlib.pyplot as plt
raw = pathlib.Path("out/sign_times_raw.csv")
assert raw.exists(), "Run ./tools/bench_sign_quick.py first."
df = pd.read_csv(raw)
df["seconds_per_sign"] = pd.to_numeric(df["seconds_per_sign"], errors="coerce")
grp = df.groupby("size_bytes")["seconds_per_sign"]
summary = grp.agg(mean_seconds="mean", std_seconds="std", n="count").reset_index()
summary["std_seconds"] = summary["std_seconds"].fillna(0.0)
summary["size_mib"] = summary["size_bytes"] / (1024*1024)
out_csv = pathlib.Path("out/sign_times_summary.csv")
summary.sort_values("size_bytes").to_csv(out_csv, index=False)
plt.figure()
plt.errorbar(summary["size_mib"], summary["mean_seconds"],
             yerr=summary["std_seconds"], fmt='-o', capsize=4)
plt.xlabel("Payload size (MiB)")
plt.ylabel("Sign time per op (s)")
plt.title("Dilithium signing time vs payload size")
plt.grid(True, which="both", linestyle=":")
plt.tight_layout()
png = pathlib.Path("out/sign_times_plot.png")
plt.savefig(png, dpi=160)
print(f"Wrote {out_csv}")
print(f"Wrote {png}")
