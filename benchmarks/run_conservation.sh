#!/usr/bin/env bash
# run_conservation.sh — Conservation-of-matter sanity check.
# Seeds a blob scene, steps the simulation, and verifies that the sand count
# is identical at every step. Reports per-step counts and a final summary for
# both implementations at sizes 256 and 1024.
# Override defaults via env vars:
#   GODOT=/path/to/godot SIZES="256 1024" ./benchmarks/run_conservation.sh
set -euo pipefail

GODOT=${GODOT:-godot}
SIZES=${SIZES:-"256 1024"}
LABEL=${LABEL:-}

# CPU: does 1 row of fall per step. GPU: 1 row per 2 phases.
# Enough steps to exercise the simulation well past initial transients.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SEQ_BIN="$REPO_ROOT/sequential/build/sand_sim"
GODOT_PROJ="$REPO_ROOT/godot_project"

if [[ ! -x "$SEQ_BIN" ]]; then
    echo "error: $SEQ_BIN not found. Build first:" >&2
    echo " cmake -S $REPO_ROOT/sequential -B $REPO_ROOT/sequential/build -DCMAKE_BUILD_TYPE=Release" >&2
    echo " cmake --build $REPO_ROOT/sequential/build -j" >&2
    exit 1
fi

if ! command -v "$GODOT" >/dev/null 2>&1; then
    echo "error: Godot binary '$GODOT' not found" >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR/results"
OUT="$SCRIPT_DIR/results/exp3a_${LABEL}.csv"
echo "writing results to: $OUT"
echo "impl,width,steps,sand_initial,sand_final,violated" > "$OUT"

field() { echo "$1" | tr ' ' '\n' | awk -F= -v k="$2" '$1==k{print $2}'; }

for SIZE in $SIZES; do
    case "$SIZE" in
        256)
            SS=512
            GS=1024
            ;;
        1024)
            SS=2048
            GS=4096
            ;;
        *)
            echo "error: unsupported size '$SIZE'" >&2
            echo "supported sizes: 256 1024" >&2
            exit 1
            ;;
    esac

    echo "== seq ${SIZE}x${SIZE}, steps=$SS =="
    LINE=$("$SEQ_BIN" --width "$SIZE" --height "$SIZE" --steps "$SS" --conservation)
    SI=$(field "$LINE" sand_initial); SF=$(field "$LINE" sand_final)
    V=$(field "$LINE" violated)
    printf "  sand_initial=%s sand_final=%s violated=%s\n" "$SI" "$SF" "$V"
    echo "seq,$SIZE,$SS,$SI,$SF,$V" >> "$OUT"
    if [[ "$V" == "true" ]]; then
        echo "FATAL: conservation violated in seq size=$SIZE" >&2
        exit 2
    fi

    echo "== gpu ${SIZE}x${SIZE}, steps=$GS =="
    LINE=$("$GODOT" --path "$GODOT_PROJ" --script res://benchmark.gd -- \
        --mode conservation --width "$SIZE" --height "$SIZE" --steps "$GS" 2>&1 \
        | grep '^CONSERVATION_SUMMARY' || true)
    if [[ -z "$LINE" ]]; then
        echo "FATAL: no CONSERVATION_SUMMARY output for gpu size=$SIZE" >&2
        echo "  (re-run the godot command without grep to see the error)" >&2
        exit 2
    fi
    SI=$(field "$LINE" sand_initial); SF=$(field "$LINE" sand_final)
    V=$(field "$LINE" violated)
    printf "  sand_initial=%s sand_final=%s violated=%s\n" "$SI" "$SF" "$V"
    echo "gpu,$SIZE,$GS,$SI,$SF,$V" >> "$OUT"
    if [[ "$V" == "true" ]]; then
        echo "FATAL: conservation violated in gpu size=$SIZE" >&2
        exit 2
    fi
done

echo "done. $OUT"