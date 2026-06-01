
"""
plotting for Experiment 1b: density/occupancy sweep.

Reads the CSV produced by run_exp1b.sh and emits two figures:
  density_cups.{png,pdf}     CUPS vs fill fraction, CPU and GPU on one log-y axis
  density_speedup.{png,pdf}  GPU/CPU speedup ratio vs fill fraction (linear)

Usage:
  python benchmarks/plot_density.py benchmarks/results/exp1b_YYYYMMDD_HHMMSS.csv
  # or omit the path to auto-pick the most recent exp1b_*.csv
"""

import sys
import glob
import os
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

OUT_DIR = Path("benchmarks/results/figures")
OUT_DIR.mkdir(parents=True, exist_ok=True)

def load(path: str) -> pd.DataFrame:
    df = pd.read_csv(path)
    # Conservation sanity (the script asserts this too, belt-and-braces).
    bad = df[df.sand_initial != df.sand_final]
    if len(bad):
        raise SystemExit(f"FATAL: {len(bad)} rows violate conservation in {path}")
    return df


def aggregate(df: pd.DataFrame) -> pd.DataFrame:
    """Per (impl, fill_nominal): mean/std of CUPS and elapsed time across reps."""
    grouped = df.groupby(["impl", "fill_nominal"])
    out = grouped["cell_updates_per_s"].agg(["mean", "std", "count"]).reset_index()
    t_stats = grouped["elapsed_s"].agg(["mean", "std"]).reset_index()
    out["t_mean"] = t_stats["mean"]
    out["t_std"] = t_stats["std"]
    out["fill_actual_mean"] = grouped["fill_actual"].mean().values
    return out


def plot_cups(agg: pd.DataFrame, outstem: Path) -> None:
    fig, ax = plt.subplots(figsize=(6.5, 4.2))
    for impl, marker, color in [("cpu", "o", "#c44"), ("gpu", "s", "#36c")]:
        sub = agg[agg.impl == impl].sort_values("fill_nominal")
        ax.errorbar(
            sub.fill_nominal, sub["mean"], yerr=sub["std"],
            marker=marker, color=color, label=impl.upper(),
            capsize=3, linewidth=1.5, markersize=6,
        )
    ax.set_xlabel("Initial fill fraction")
    ax.set_ylabel("Cell updates per second (CUPS)")
    ax.set_yscale("log")
    ax.set_title("Throughput vs initial density (1024×1024)")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend(loc="center right")
    fig.tight_layout()
    for ext in ("png", "pdf"):
        fig.savefig(f"{outstem}.{ext}", dpi=150)
    print(f"  wrote {outstem}.png / .pdf")


def plot_speedup(agg_with_time: pd.DataFrame, outstem: Path) -> None:
    cpu = agg_with_time[agg_with_time.impl == "cpu"].set_index("fill_nominal").sort_index()
    gpu = agg_with_time[agg_with_time.impl == "gpu"].set_index("fill_nominal").sort_index()
    assert (cpu.index == gpu.index).all(), "impls disagree on fill grid"

    # Speedup as runtime ratio: how many times longer the CPU takes than the GPU.
    speedup = cpu["t_mean"].values / gpu["t_mean"].values
    # Error propagation for a ratio of independent means.
    rel_err = np.sqrt(
        (cpu["t_std"].values / cpu["t_mean"].values) ** 2
        + (gpu["t_std"].values / gpu["t_mean"].values) ** 2
    )
    speedup_err = speedup * rel_err

    fig, ax = plt.subplots(figsize=(6.5, 4.2))
    ax.errorbar(
        cpu.index, speedup, yerr=speedup_err,
        marker="D", color="#262", capsize=3, linewidth=1.5, markersize=6,
    )
    ax.set_xlabel("Initial fill fraction")
    ax.set_ylabel(r"Speedup  ($t_{\mathrm{CPU}} / t_{\mathrm{GPU}}$)")
    ax.set_title("GPU advantage grows with density (1024×1024)")
    ax.grid(True, alpha=0.3)
    for x, y in zip(cpu.index, speedup):
        ax.annotate(f"{y:.1f}×", (x, y), textcoords="offset points",
                    xytext=(7, 4), fontsize=9)
    fig.tight_layout()
    for ext in ("png", "pdf"):
        fig.savefig(f"{outstem}.{ext}", dpi=150)
    print(f"  wrote {outstem}.png / .pdf")


def print_table(agg: pd.DataFrame) -> None:
    cpu = agg[agg.impl == "cpu"].set_index("fill_nominal").sort_index()
    gpu = agg[agg.impl == "gpu"].set_index("fill_nominal").sort_index()
    speedup = cpu["t_mean"].values / gpu["t_mean"].values
    print()
    print(f"  {'fill':>5}  {'t_CPU (s)':>10}  {'t_GPU (s)':>10}  "
          f"{'CPU CUPS':>12}  {'GPU CUPS':>12}  {'speedup':>8}")
    print(f"  {'-'*5}  {'-'*10}  {'-'*10}  {'-'*12}  {'-'*12}  {'-'*8}")
    for f, tc, tg, cc, cg, s in zip(
        cpu.index, cpu["t_mean"], gpu["t_mean"],
        cpu["mean"], gpu["mean"], speedup,
    ):
        print(f"  {f:>5.2f}  {tc:>10.4f}  {tg:>10.4f}  "
              f"{cc:>12.3e}  {cg:>12.3e}  {s:>7.1f}x")
    print()


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        candidates = sorted(glob.glob("benchmarks/results/exp1b_*.csv"))
        if not candidates:
            raise SystemExit("no benchmarks/results/exp1b_*.csv found")
        path = candidates[-1]
        print(f"using most recent: {path}")

    df = load(path)
    agg = aggregate(df)
    print_table(agg)

    outdir = Path(path).parent
    stem = Path(path).stem  # e.g. density_20260601_142233
    plot_cups(agg, OUT_DIR / "exp1b_cups")
    plot_speedup(agg, OUT_DIR / "exp1b_speedup")


if __name__ == "__main__":
    main()