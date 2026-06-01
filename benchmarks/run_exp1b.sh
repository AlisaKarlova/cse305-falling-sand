#!/usr/bin/env bash
# run_exp1b.sh - Experiment 1b: density/occupancy sweep at fixed grid size.
# Runs both the C++ sequential and Godot GPU benchmarks at varying --fill
# fractions, writes one combined CSV row per (impl, fill, rep).
#
# Override defaults via env vars:
#   REPS=5 FILLS="0.01 0.05 0.25 0.50 0.75" SIZE=1024 STEPS=200 ./benchmarks/run_density.sh

set -euo pipefail

GODOT=${GODOT:-godot}
REPS=${REPS:-5}
SIZE=${SIZE:-1024}
STEPS=${STEPS:-200}
WARMUP=${WARMUP:-5}
FILLS=${FILLS:-"0.01 0.05 0.25 0.50 0.75"}
CHUNK=${CHUNK:-0}
# Pinned seed so C++ and GPU see the SAME initial grid at every (fill, rep).
SEED=${SEED:-0xC5E305}
LABEL=${LABEL:-}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/sequential/build/sand_sim"
PROJECT="$REPO_ROOT/godot_project"

if [[ ! -x "$BIN" ]]; then
    echo "error: $BIN not found; build the sequential target first" >&2; exit 1
fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
    echo "error: Godot binary '$GODOT' not found; set GODOT=/path/to/godot" >&2; exit 1
fi

mkdir -p "$SCRIPT_DIR/results"
OUT="$SCRIPT_DIR/results/exp1b_${LABEL}.csv"
echo "writing results to: $OUT"

echo "impl,width,height,fill_nominal,fill_actual,steps,warmup,rep,elapsed_s,cell_updates_per_s,sand_initial,sand_final" > "$OUT"

field() { echo "$1" | tr ' ' '\n' | awk -F= -v k="$2" '$1==k{print $2}'; }

run_seq() {
    local FILL=$1 REP=$2
    "$BIN" --width "$SIZE" --height "$SIZE" --steps "$STEPS" \
           --warmup "$WARMUP" --seed "$((SEED + REP))" --fill "$FILL" --benchmark
}

run_gpu() {
    local FILL=$1 REP=$2
    "$GODOT" --rendering-driver metal --path "$PROJECT" --script res://benchmark.gd -- \
             --width "$SIZE" --height "$SIZE" --steps "$STEPS" \
             --warmup "$WARMUP" --seed "$((SEED + REP))" --fill "$FILL" --chunk "$CHUNK" 2>&1 \
        | grep '^BENCH' || true
}

emit_row() {
    local IMPL=$1 FILL=$2 REP=$3 LINE=$4
    if [[ -z "$LINE" ]]; then
        echo "FATAL: no BENCH output for impl=$IMPL fill=$FILL rep=$REP" >&2; exit 2
    fi
    local W H S WM E C SI SF FA
    W=$(field  "$LINE" width)
    H=$(field  "$LINE" height)
    S=$(field  "$LINE" steps)
    WM=$(field "$LINE" warmup)
    E=$(field  "$LINE" elapsed_s)
    C=$(field  "$LINE" cell_updates_per_s)
    SI=$(field "$LINE" sand_initial)
    SF=$(field "$LINE" sand_final)
    if [[ "$SI" != "$SF" ]]; then
        echo "FATAL: conservation violation impl=$IMPL fill=$FILL rep=$REP  sand $SI -> $SF" >&2; exit 2
    fi
    # Actual realised density (Bernoulli draw deviates slightly from nominal).
    FA=$(awk -v si="$SI" -v n="$((SIZE * SIZE))" 'BEGIN{printf "%.6f", si/n}')
    echo "$IMPL,$W,$H,$FILL,$FA,$S,$WM,$REP,$E,$C,$SI,$SF" >> "$OUT"
    printf "  %-3s fill=%-5s rep=%d  %.4fs  (%.3e cups)  sand=%s\n" "$IMPL" "$FILL" "$REP" "$E" "$C" "$SI"
}

for FILL in $FILLS; do
    for REP in $(seq 1 "$REPS"); do
        emit_row "cpu" "$FILL" "$REP" "$(run_seq "$FILL" "$REP")"
        emit_row "gpu" "$FILL" "$REP" "$(run_gpu "$FILL" "$REP")"
    done
done

echo "done. $OUT"