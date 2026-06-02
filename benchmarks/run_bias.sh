#!/usr/bin/env bash
# run_bias.sh — Symmetry sanity check.
# Drops a single centered blob, lets it settle, reports (L - R) / total
# for both implementations at sizes 256 and 1024. Center column excluded
# from both halves so the partition is invariant under reflection.
# Override defaults via env vars:
#   GODOT=/path/to/godot SIZES="256 1024" ./benchmarks/run_bias.sh

set -euo pipefail

GODOT=${GODOT:-godot}
SIZES=${SIZES:-"256 1024"}
LABEL=${LABEL:-}

# CPU: does 1 row of fall per step. GPU: 1 row per 2 phases.
# Both lists are generous so the pile is fully settled before we measure.


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SEQ_BIN="$REPO_ROOT/sequential/build/sand_sim"
GODOT_PROJ="$REPO_ROOT/godot_project"

if [[ ! -x "$SEQ_BIN" ]]; then
    echo "error: $SEQ_BIN not found. Build first:" >&2
    echo "  cmake -S $REPO_ROOT/sequential -B $REPO_ROOT/sequential/build -DCMAKE_BUILD_TYPE=Release" >&2
    echo "  cmake --build $REPO_ROOT/sequential/build -j" >&2
    exit 1
fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
    echo "error: Godot binary '$GODOT' not found" >&2
    exit 1
fi

mkdir -p "$SCRIPT_DIR/results"
OUT="$SCRIPT_DIR/results/exp2a_${LABEL}.csv"
echo "writing results to: $OUT"
echo "impl,width,steps,left,right,total,rel_diff" > "$OUT"

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
    LINE=$("$SEQ_BIN" --width "$SIZE" --height "$SIZE" --steps "$SS" --bias)
    L=$(field "$LINE" left); R=$(field "$LINE" right)
    T=$(field "$LINE" total); D=$(field "$LINE" rel_diff)
    printf "  L=%s R=%s total=%s rel_diff=%s\n" "$L" "$R" "$T" "$D"
    echo "seq,$SIZE,$SS,$L,$R,$T,$D" >> "$OUT"

    echo "== gpu ${SIZE}x${SIZE}, steps=$GS =="
    LINE=$("$GODOT" --path "$GODOT_PROJ" --script res://benchmark.gd -- \
                    --mode bias --width "$SIZE" --height "$SIZE" --steps "$GS" 2>&1 \
           | grep '^BIAS' || true)
    if [[ -z "$LINE" ]]; then
        echo "FATAL: no BIAS output for gpu size=$SIZE" >&2
        echo "  (re-run the godot command without grep to see the error)" >&2
        exit 2
    fi
    L=$(field "$LINE" left); R=$(field "$LINE" right)
    T=$(field "$LINE" total); D=$(field "$LINE" rel_diff)
    printf "  L=%s R=%s total=%s rel_diff=%s\n" "$L" "$R" "$T" "$D"
    echo "gpu,$SIZE,$GS,$L,$R,$T,$D" >> "$OUT"
done

echo "done. $OUT"