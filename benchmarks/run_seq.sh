#!/usr/bin/env bash
# run_seq.sh — Sequential CPU benchmark sweep.
# Runs sand_sim --benchmark across several grid sizes, repeats each
# config REPS times, writes one CSV row per repetition to a timestamped
# file under benchmarks/results/.
#
# Override defaults via env vars:
#   REPS=10 SIZES="128 256 512 1024" STEPS=200 ./benchmarks/run_seq.sh

set -euo pipefail

REPS=${REPS:-5}
STEPS=${STEPS:-500}
WARMUP=${WARMUP:-5}
SIZES=${SIZES:-"64 128 256 512 1024"}

# Resolve paths from the script's location so it works no matter where
# you invoke it from (CI, IDE, repo root, etc).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/sequential/build/sand_sim"

if [[ ! -x "$BIN" ]]; then
    echo "error: $BIN not found or not executable" >&2
    echo "build the sequential target first:" >&2
    echo "  cmake -S $REPO_ROOT/sequential -B $REPO_ROOT/sequential/build -DCMAKE_BUILD_TYPE=Release" >&2
    echo "  cmake --build $REPO_ROOT/sequential/build -j" >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR/results"
OUT="$SCRIPT_DIR/results/seq_$(date +%Y%m%d_%H%M%S).csv"
echo "writing results to: $OUT"

echo "width,height,steps,warmup,rep,elapsed_s,cell_updates_per_s,sand_initial,sand_final,wood_initial,wood_final" > "$OUT"

field() { echo "$1" | tr ' ' '\n' | awk -F= -v k="$2" '$1==k{print $2}'; }

for SIZE in $SIZES; do
    for REP in $(seq 1 "$REPS"); do
        LINE=$("$BIN" --width "$SIZE" --height "$SIZE" \
                      --steps "$STEPS" --warmup "$WARMUP" --benchmark)
        W=$(field  "$LINE" width)
        H=$(field  "$LINE" height)
        S=$(field  "$LINE" steps)
        WM=$(field "$LINE" warmup)
        E=$(field  "$LINE" elapsed_s)
        C=$(field  "$LINE" cell_updates_per_s)
        SI=$(field "$LINE" sand_initial)
        SF=$(field "$LINE" sand_final)
        WI=$(field "$LINE" wood_initial)
        WF=$(field "$LINE" wood_final)

        if [[ "$SI" != "$SF" || "$WI" != "$WF" ]]; then
            echo "FATAL: conservation violation at size=${SIZE}x${SIZE} rep=$REP" >&2
            echo "  sand $SI -> $SF, wood $WI -> $WF" >&2
            exit 2
        fi

        echo "$W,$H,$S,$WM,$REP,$E,$C,$SI,$SF,$WI,$WF" >> "$OUT"
        printf "  %5dx%-5d rep=%d  %.4fs  (%.2e cups)\n" "$SIZE" "$SIZE" "$REP" "$E" "$C"
    done
done

echo "done. $OUT"
