# Plotting for exp1a, done using claude code

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import sys
from pathlib import Path

# ── CONFIG ────────────────────────────────────────────────────────────────────
SEQ_CSV = "benchmarks/results/exp1a_seq.csv"  
GPU_CSV = "benchmarks/results/exp1a_gpu.csv" 
OUT_DIR = Path("benchmarks/results/figures")
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── LOAD ──────────────────────────────────────────────────────────────────────
seq = pd.read_csv(SEQ_CSV)
gpu = pd.read_csv(GPU_CSV)
seq["impl"] = "CPU"
gpu["impl"] = "GPU"
df = pd.concat([seq, gpu], ignore_index=True)

# Sanity check: all rows should have the same steps value
assert df["steps"].nunique() == 1, "Mixed step counts in CSV — something went wrong"

# ── AGGREGATE ────────────────────────────────────────────────────────────────
# Group by implementation + grid size, compute median CUPS and IQR
def agg(group):
    cups = group["cell_updates_per_s"]
    return pd.Series({
        "median_cups": cups.median(),
        "q25":         cups.quantile(0.25),
        "q75":         cups.quantile(0.75),
        "min_cups":    cups.min(),
        "max_cups":    cups.max(),
        "n":           len(cups),
    })

stats = (
    df.groupby(["impl", "width"])
      .apply(agg)
      .reset_index()
)
stats["grid_cells"] = stats["width"] ** 2   # N = width*height (square grids)

print(stats.to_string(index=False))

# ── PLOT 1: CUPS vs grid size (log-log) ───────────────────────────────────────
fig, ax = plt.subplots(figsize=(7, 4.5))

for impl, color in [("CPU", "#2166ac"), ("GPU", "#d6604d")]:
    s = stats[stats["impl"] == impl].sort_values("width")
    xs = s["grid_cells"].values
    ys = s["median_cups"].values
    lo = ys - s["q25"].values        # IQR lower error
    hi = s["q75"].values - ys        # IQR upper error

    ax.loglog(xs, ys, "o-", color=color, label=impl, linewidth=1.8, markersize=5)
    ax.fill_between(xs, s["q25"].values, s["q75"].values,
                    alpha=0.18, color=color)

ax.set_xlabel("Grid cells (N = width²)")
ax.set_ylabel("Nominal CUPS (cell-updates / s)")
ax.set_title("Experiment 1a — Throughput scaling")
ax.legend()
ax.grid(True, which="both", linestyle="--", linewidth=0.4, alpha=0.6)

# Label x-axis ticks as "WxW" for readability
widths = sorted(df["width"].unique())
ax.set_xticks([w**2 for w in widths])
ax.set_xticklabels([f"{w}²" for w in widths], fontsize=8)

fig.tight_layout()
fig.savefig(OUT_DIR / "exp1a_cups_scaling.pdf", dpi=150)
fig.savefig(OUT_DIR / "exp1a_cups_scaling.png", dpi=150)
print("Saved: exp1a_cups_scaling")

# ── PLOT 2: Speedup ratio vs grid size (based on elapsed_s) ───────────────────
def agg_time(group):
    t = group["elapsed_s"]
    return pd.Series({
        "median_t": t.median(),
        "q25":      t.quantile(0.25),
        "q75":      t.quantile(0.75),
    })

tstats = (
    df.groupby(["impl", "width"])
      .apply(agg_time)
      .reset_index()
)
# Speedup = cpu_time / gpu_time (>1 means GPU is faster)
# Using tstats which was computed over elapsed_s
cpu_t = tstats[tstats["impl"] == "CPU"].set_index("width")
gpu_t = tstats[tstats["impl"] == "GPU"].set_index("width")
common_widths = sorted(cpu_t.index.intersection(gpu_t.index))

speedup = cpu_t.loc[common_widths, "median_t"] / gpu_t.loc[common_widths, "median_t"]

# IQR band: conservative range — CPU fast / GPU slow vs CPU slow / GPU fast
speedup_lo = cpu_t.loc[common_widths, "q25"] / gpu_t.loc[common_widths, "q75"]
speedup_hi = cpu_t.loc[common_widths, "q75"] / gpu_t.loc[common_widths, "q25"]

xs = [w**2 for w in common_widths]

fig, ax = plt.subplots(figsize=(7, 4))
ax.semilogx(xs, speedup.values, "s-", color="#1a9641", linewidth=1.8, markersize=5, label="CPU / GPU")
ax.fill_between(xs, speedup_lo.values, speedup_hi.values, alpha=0.18, color="#1a9641", label="IQR band")
ax.axhline(1.0, color="black", linewidth=0.8, linestyle="--", label="Parity (1×)")

ax.set_xlabel("Grid cells (N = width²)")
ax.set_ylabel("Speedup (CPU time / GPU time)")
ax.set_title("Experiment 1a — GPU speedup ratio")
ax.legend()
ax.grid(True, which="both", linestyle="--", linewidth=0.4, alpha=0.6)

ax.set_xticks(xs)
ax.set_xticklabels([f"{w}²" for w in common_widths], fontsize=8)

fig.tight_layout()
fig.savefig(OUT_DIR / "exp1a_speedup.pdf", dpi=150)
fig.savefig(OUT_DIR / "exp1a_speedup.png", dpi=150)
print("Saved: exp1a_speedup")


# ── PLOT 3: Elapsed time vs grid size ─────────────────────────────────────────


fig, ax = plt.subplots(figsize=(7, 4.5))

for impl, color in [("CPU", "#2166ac"), ("GPU", "#d6604d")]:
    s = tstats[tstats["impl"] == impl].sort_values("width")
    xs = [w**2 for w in s["width"].values]
    ys = s["median_t"].values

    ax.loglog(xs, ys, "o-", color=color, label=impl, linewidth=1.8, markersize=5)
    ax.fill_between(xs, s["q25"].values, s["q75"].values,
                    alpha=0.18, color=color)

ax.set_xlabel("Grid cells (N = width²)")
ax.set_ylabel("Elapsed time (s)")
ax.set_title(f"Experiment 1a — Wall-clock time for {df['steps'].iloc[0]} steps")
ax.legend()
ax.grid(True, which="both", linestyle="--", linewidth=0.4, alpha=0.6)

widths = sorted(df["width"].unique())
ax.set_xticks([w**2 for w in widths])
ax.set_xticklabels([f"{w}²" for w in widths], fontsize=8)

fig.tight_layout()
fig.savefig(OUT_DIR / "exp1a_elapsed.pdf", dpi=150)
fig.savefig(OUT_DIR / "exp1a_elapsed.png", dpi=150)
print("Saved: exp1a_elapsed")

# ── PRINT CROSSOVER ───────────────────────────────────────────────────────────
crossover = [(w, speedup[w]) for w in common_widths if speedup[w] >= 1.0]
if crossover:
    w0, s0 = crossover[0]
    print(f"\nGPU breaks even at width={w0} ({w0}²={w0**2} cells), speedup={s0:.2f}×")
else:
    print("\nGPU never reaches parity in this size range — extend SIZES upward")

plt.show()