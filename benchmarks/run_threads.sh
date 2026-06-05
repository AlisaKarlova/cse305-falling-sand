#!/usr/bin/env bash
# run_threads.sh — CPU thread-scaling sweep for the Margolus implementation.
# Runs sand_sim --impl margolus --benchmark across grid sizes and thread
# counts, REPS times each; one CSV row per repetition.
#
# Override defaults via env vars:
#   REPS=10 SIZES="256 512 1024" THREADS="1 2 3 4" STEPS=500 LABEL=run1 ./benchmarks/run_threads.sh
set -euo pipefail

REPS=${REPS:-5}
STEPS=${STEPS:-500}
WARMUP=${WARMUP:-5}
SIZES=${SIZES:-"128 256 512 1024"}
THREADS=${THREADS:-"1 2 4 8 14 16"}
LABEL=${LABEL:-}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/sequential/build/sand_sim"

if [[ ! -x "$BIN" ]]; then
    echo "error: $BIN not found; build the sequential target first:" >&2
    echo "  cmake -S $REPO_ROOT/sequential -B $REPO_ROOT/sequential/build -DCMAKE_BUILD_TYPE=Release" >&2
    echo "  cmake --build $REPO_ROOT/sequential/build -j" >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR/results"
if [[ -n "$LABEL" ]]; then
    OUT="$SCRIPT_DIR/results/threads_${LABEL}.csv"
else
    OUT="$SCRIPT_DIR/results/threads_$(date +%Y%m%d_%H%M%S).csv"
fi
echo "writing results to: $OUT"

echo "impl,threads,width,height,steps,warmup,rep,elapsed_s,cell_updates_per_s,sand_initial,sand_final" > "$OUT"

field() { echo "$1" | tr ' ' '\n' | awk -F= -v k="$2" '$1==k{print $2}'; }

for SIZE in $SIZES; do
  for T in $THREADS; do
    for REP in $(seq 1 "$REPS"); do
      LINE=$("$BIN" --impl margolus --threads "$T" \
                    --width "$SIZE" --height "$SIZE" \
                    --steps "$STEPS" --warmup "$WARMUP" --benchmark)
      IMPL=$(field "$LINE" impl)
      TH=$(field  "$LINE" threads)
      W=$(field   "$LINE" width)
      H=$(field   "$LINE" height)
      S=$(field   "$LINE" steps)
      WM=$(field  "$LINE" warmup)
      E=$(field   "$LINE" elapsed_s)
      C=$(field   "$LINE" cell_updates_per_s)
      SI=$(field  "$LINE" sand_initial)
      SF=$(field  "$LINE" sand_final)

      if [[ "$SI" != "$SF" ]]; then
        echo "FATAL: conservation violation size=${SIZE} threads=$T rep=$REP  sand $SI -> $SF" >&2
        exit 2
      fi

      echo "$IMPL,$TH,$W,$H,$S,$WM,$REP,$E,$C,$SI,$SF" >> "$OUT"
      printf "  %5dx%-5d t=%s rep=%d  %.4fs  (%.2e cups)\n" "$SIZE" "$SIZE" "$T" "$REP" "$E" "$C"
    done
  done
done

echo "done. $OUT"