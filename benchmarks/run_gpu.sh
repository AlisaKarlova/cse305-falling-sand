#!/usr/bin/env bash
# run_gpu.sh — GPU (Godot/Margolus) benchmark sweep.
# The GPU counterpart to run_seq.sh: runs the headless benchmark.gd across
# several grid sizes, repeats each config REPS times, and writes one CSV row
# per repetition to a timestamped file under benchmarks/results/.
#
# Override defaults via env vars:
#   GODOT=/path/to/godot REPS=10 SIZES="128 256 512 1024" STEPS=200 ./benchmarks/run_gpu.sh

set -euo pipefail

GODOT=${GODOT:-godot}
REPS=${REPS:-5}
STEPS=${STEPS:-500}
WARMUP=${WARMUP:-5}
SIZES=${SIZES:-"64 128 256 512 1024"}
# submit/sync every CHUNK steps; 0 = one submission for the whole batch.
# Raise this (e.g. 100) if a large config triggers a GPU driver timeout (TDR).
CHUNK=${CHUNK:-0}

# Resolve paths from the script's location so it works no matter where it's
# invoked from (CI, IDE, repo root, etc).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/godot_project"

if ! command -v "$GODOT" >/dev/null 2>&1; then
    echo "error: Godot binary '$GODOT' not found" >&2
    echo "set GODOT=/path/to/godot and retry" >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR/results"
OUT="$SCRIPT_DIR/results/gpu_$(date +%Y%m%d_%H%M%S).csv"
echo "writing results to: $OUT"

echo "width,height,steps,warmup,rep,elapsed_s,cell_updates_per_s,sand_initial,sand_final,wood_initial,wood_final" > "$OUT"

field() { echo "$1" | tr ' ' '\n' | awk -F= -v k="$2" '$1==k{print $2}'; }

for SIZE in $SIZES; do
    for REP in $(seq 1 "$REPS"); do
        # Godot prints startup noise; keep only the single BENCH line.
        LINE=$("$GODOT" --path "$PROJECT" --script res://benchmark.gd -- \
                        --width "$SIZE" --height "$SIZE" \
                        --steps "$STEPS" --warmup "$WARMUP" --chunk "$CHUNK" 2>&1 \
               | grep '^BENCH' || true)

        if [[ -z "$LINE" ]]; then
            echo "FATAL: no BENCH output at size=${SIZE}x${SIZE} rep=$REP" >&2
            echo "  (run the command without the grep to see Godot's error output)" >&2
            exit 2
        fi

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