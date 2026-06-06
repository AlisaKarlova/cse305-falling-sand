# CSE305 Project — Falling Sand Simulation

A cellular-automaton "falling sand" simulation, implemented two ways so the
two can be benchmarked head-to-head on identical workloads:

1. **Sequential C++ CPU baseline** — a single binary (`sand_sim`) that contains
   *two* CPU algorithms (a row-scan rule and a CPU port of the Margolus
   block-automaton), plus a terminal animation and several benchmarking regimes.
2. **Parallel GPU implementation** — a Godot 4.6 project that runs the Margolus
   rule as a compute shader (`sand.glsl`), available both as an interactive,
   mouse-paintable window and as a headless benchmark driver.

Both implementations model the same cell types and seed byte-identical initial
scenes, so their timings (CUPS — *cell updates per second*) are directly
comparable, and both run a **conservation check** (sand grains in == grains out)
that fails loudly on any regression.

---

## Repository layout

```
sequential/        C++ baseline: row-scan + Margolus CPU algorithms, terminal viewer, benchmarks
  include/         grid.h, simulation.h (row-scan), margolus.h, viewer.h
  src/             main.cpp (CLI + run modes), grid.cpp, simulation.cpp, margolus.cpp
  CMakeLists.txt
godot_project/     Godot 4.6 project: GPU Margolus compute shader
  sand.glsl        the Margolus sand compute shader (current)
  sand_old.glsl    earlier version of the shader (reference only, not loaded)
  gol.glsl         a standalone Game-of-Life compute shader (auxiliary experiment)
  texture_rect.gd  interactive window driver (paint + run/pause/step)
  benchmark.gd     headless benchmark / bias driver (no window)
  main.tscn        scene wired to texture_rect.gd
benchmarks/        sweep scripts (*.sh), plotting scripts (*.py), results/ CSVs + figures
report/            LaTeX write-up (main.tex) and figures
```

---

## Cell model (shared by both implementations)

| Value | Type  | Behaviour                                                     |
|-------|-------|--------------------------------------------------------------|
| 0     | Empty | Free space; sand falls into it.                              |
| 1     | Sand  | Falls down, then diagonally; conserved.                     |
| 2     | Water | Modelled in the Margolus rules (spreads horizontally). Only the GPU interactive brush seeds it; the benchmarks seed sand only. |
| 3     | Wood  | Static obstacle; never moves. Out-of-bounds reads are treated as Wood, so the grid border acts as a wall. |

Coordinates are `(row, col)` with **row 0 at the top**; sand falls in the
`+row` direction. In the GPU texture, grid state lives in an `RGBA32F` image
where the **red channel** encodes the cell type.

---

# 1. Sequential C++ baseline

## 1.1 Build

```sh
cmake -S sequential -B sequential/build -DCMAKE_BUILD_TYPE=Release
cmake --build sequential/build -j
```

The binary is `sequential/build/sand_sim`.

### Optional SDL2 viewer (experimental)

`CMakeLists.txt` exposes `-DENABLE_VIEWER=ON`, which compiles `src/viewer.cpp`
and links SDL2 for a real graphical window (the `--viewer` flag). This is an
optional code path; if `src/viewer.cpp` is not present or SDL2 is not installed (like on Salle info machines),
leave the option `OFF` (the default) and use the built-in terminal animation
instead.

```sh
cmake -S sequential -B sequential/build -DCMAKE_BUILD_TYPE=Release -DENABLE_VIEWER=ON
```

## 1.2 The two CPU algorithms (`--impl`)

The binary contains two independent simulation cores. Choose with `--impl`:

### `--impl scan` (default) — double-buffered row-scan rule
Implemented in `simulation.cpp`.

### `--impl margolus` — CPU port of the GPU shader
Implemented in `margolus.cpp`.


> `--impl` only takes effect in **`--benchmark`** mode. The interactive terminal
> animation and the `--bias` regime always use the `scan` core.

## 1.3 Run modes (regimes)

The mode is chosen by flags, evaluated in this precedence: `--viewer` ->
`--bias` -> `--benchmark` -> (default) interactive terminal.

### (a) Interactive terminal animation — *default, no flag*
Zero-dependency ANSI animation, handy for eyeballing the physics. Scene:
three sand blobs near the top falling onto a **wood platform with a central gap**
(exercises straight-fall, diagonal-fall, and collision with a static obstacle).
Renders `' '`=empty, `'.'`=sand, `'#'`=wood, sleeping `--delay` ms between frames.

```sh
# default 200x200, ~60 fps, 1000 steps
./sequential/build/sand_sim

# smaller, slower, easier to watch
./sequential/build/sand_sim --width 80 --height 40 --steps 600 --delay 30
```

### (b) Benchmark mode — `--benchmark`
Runs `--warmup` untimed steps, then times `--steps`
steps with a single wall-clock span and prints one line:

```
BENCH impl=scan threads=1 width=512 height=512 steps=500 warmup=5 \
      elapsed_s=... cell_updates_per_s=... sand_initial=... sand_final=... wood_initial=0 wood_final=0
```

Scene is the same three sand blobs **without wood** (so CPU and GPU seed an
identical sand-only state). With `--fill F` the scene is replaced by a random
Bernoulli fill at density `F` (reproducible per `--seed`). Exits non-zero on a
conservation violation.

```sh
# row-scan core
./sequential/build/sand_sim --width 512 --height 512 --steps 500 --benchmark

# Margolus core on 8 threads
./sequential/build/sand_sim --impl margolus --threads 8 \
    --width 1024 --height 1024 --steps 500 --benchmark

# random 25%-filled grid instead of blobs
./sequential/build/sand_sim --fill 0.25 --width 1024 --height 1024 --steps 200 --benchmark
```

### (c) Symmetry / bias regime — `--bias`
Drops a **single centered blob**, runs `--steps` steps (always the `scan` core),
then counts sand strictly left vs. strictly right of the centre column (centre
column excluded so the partition is reflection-invariant). Prints:

```
BIAS impl=seq width=... height=... steps=... left=... right=... total=... rel_diff=(L-R)/total
```

It asserts the seed itself is perfectly symmetric and checks conservation.

```sh
./sequential/build/sand_sim --bias --width 256 --height 256 --steps 512
```

### (d) SDL2 viewer — `--viewer` *(only if built with `-DENABLE_VIEWER=ON`)*
Opens a real graphical window. Without the viewer build it prints an error and
exits.

## 1.4 Full flag reference

| Flag           | Default     | Meaning                                                                 |
|----------------|-------------|-------------------------------------------------------------------------|
| `--width N`    | 200         | Grid width.                                                             |
| `--height N`   | 200         | Grid height.                                                            |
| `--steps N`    | 1000        | Number of simulation steps.                                            |
| `--impl S`     | `scan`      | Algorithm: `scan` (row-scan, stochastic) or `margolus` (deterministic). *Benchmark mode only.* |
| `--threads N`  | 1           | Worker threads for the **Margolus** core. Ignored by `scan`. (`N >= 1`.) |
| `--benchmark`  | off         | Timed, no rendering; prints the `BENCH` line.                          |
| `--bias`       | off         | Symmetry regime; prints the `BIAS` line.                               |
| `--viewer`     | off         | SDL2 window (requires `ENABLE_VIEWER` build).                          |
| `--fill F`     | 0.0         | Random Bernoulli fill at density `F` in `[0,1]`; replaces the blob scene (benchmark mode). |
| `--warmup N`   | 5           | Untimed warmup steps before the timed region.                          |
| `--seed N`     | `0xC5E305`  | RNG seed (scan core + random fill). Accepts `0x...` hex.                |
| `--delay MS`   | 16          | Per-frame sleep in the interactive terminal (~60 fps).                 |
| `-h`, `--help` |             | Print usage.                                                           |

Run `./sequential/build/sand_sim --help` for the same list.

---

# 2. GPU implementation (Godot 4.6)

The GPU version runs the **Margolus** rule as a compute shader
(`godot_project/sand.glsl`): one shader invocation per 2×2 block, workgroup size
16×16, with the same four phase offsets as the CPU port. Grid state is a single
read-write `RGBA32F` storage image; a push-constant carries
`(offset_x, offset_y, width, height)` each step. Requires a Vulkan/Metal/D3D12
capable GPU (the project ships configured for the Forward+/RenderingDevice path).

You need a **Godot 4.6** binary (editor or headless). Two ways to run it:

## 2.1 Interactive window (`texture_rect.gd` + `main.tscn`)

Open the project and run the main scene:

```sh
godot --path godot_project          # opens the project / runs main.tscn
```

| Input                | Action                                             |
|----------------------|----------------------------------------------------|
| **Space**            | Run / pause the simulation.                         |
| **Right Arrow**      | Advance a single step (while paused).               |
| **Left mouse drag**  | Paint into the grid with the current brush.         |
| **1 / 2 / 3 / 0**    | Brush = sand / water / wood / empty (eraser).       |
| **5 / 6 / 7**        | Brush radius = 3 / 10 / 50.                          |

`FRAMES_PER_UPDATE` in the script throttles the sim speed (1 = fastest).

## 2.2 Headless benchmark / bias driver (`benchmark.gd`)

```sh
# benchmark regime (default --mode bench)
godot --path godot_project --script res://benchmark.gd -- \
      --width 512 --height 512 --steps 500 --warmup 5

# symmetry regime
godot --path godot_project --script res://benchmark.gd -- \
      --mode bias --width 256 --height 256 --steps 1024
```

> Everything after `--` is passed to the script. On Linux/Windows you may
> need to select a driver, e.g. `--rendering-driver vulkan`; the sweep scripts
> below default to `metal` (macOS) — override as needed.

### `benchmark.gd` flags

| Flag         | Default    | Meaning                                                                 |
|--------------|------------|-------------------------------------------------------------------------|
| `--width N`  | 200        | Grid width.                                                            |
| `--height N` | 200        | Grid height.                                                           |
| `--steps N`  | 1000       | Timed steps.                                                           |
| `--warmup N` | 5          | Untimed warmup steps.                                                  |
| `--seed N`   | `0xC5E305` | Seed for `--fill` (the GPU rule itself is deterministic).             |
| `--fill F`   | 0.0        | Random Bernoulli fill at density `F`; replaces the blob scene.        |
| `--chunk N`  | 0          | Submit/sync every `N` steps (`0` = one submission for the whole batch). Raise (e.g. 100) if a large run trips a GPU driver timeout (TDR). |
| `--mode S`   | `bench`    | `bench` (timed CUPS) or `bias` (left/right symmetry).                  |

## 2.3 Auxiliary shaders

- `sand_old.glsl` — an earlier revision of the sand rule, kept for reference;
  not loaded by the scene or the benchmark.
- `gol.glsl` — a standalone Conway's Game-of-Life compute shader (separate
  ping-pong `input_grid`/`output_grid`), included as an extra experiment; not
  part of the sand pipeline.

---

# 3. Benchmarks & experiments

All sweep scripts live in `benchmarks/`, resolve paths relative to themselves
(run them from anywhere), write timestamped CSVs to `benchmarks/results/`
(or `*_LABEL.csv` if `LABEL` is set), enforce the conservation invariant, and
print a per-row progress line. Build the C++ binary first; GPU scripts need a
`godot` on `PATH` (or `GODOT=/path/to/godot`).

| Script           | What it sweeps                                                        | Key env vars                                          |
|------------------|----------------------------------------------------------------------|-------------------------------------------------------|
| `run_seq.sh`     | **exp1a (CPU):** `scan` elapsed_s vs grid size.                           | `REPS STEPS WARMUP SIZES LABEL`                       |
| `run_gpu.sh`     | **exp1a (GPU):** Margolus shader elapsed_s vs grid size.                  | `GODOT REPS STEPS WARMUP SIZES CHUNK LABEL`           |
| `run_threads.sh` | CPU **Margolus thread scaling** (`--impl margolus`) over sizes x threads. | `REPS STEPS WARMUP SIZES THREADS LABEL`           |
| `run_exp1b.sh`   | **exp1b:** density sweep — sequential & GPU at varying `--fill`, fixed size. | `GODOT REPS SIZE STEPS WARMUP FILLS CHUNK SEED LABEL` |
| `run_bias.sh`    | **exp2a:** left/right symmetry for both impls at sizes 256 & 1024.    | `GODOT SIZES LABEL`                                    |

Examples:

```sh
# CPU scaling sweep
REPS=10 SIZES="128 256 512 1024" STEPS=200 LABEL=baseline ./benchmarks/run_seq.sh

# GPU scaling sweep (pick your driver inside the script / via GODOT)
GODOT=/path/to/godot SIZES="128 256 512 1024" LABEL=rtx4090 ./benchmarks/run_gpu.sh

# Margolus CPU thread scaling
THREADS="1 2 4 8 16" SIZES="512 1024" ./benchmarks/run_threads.sh

# density sweep (CPU + GPU, same seeded grids)
FILLS="0.01 0.05 0.25 0.50 0.75" SIZE=1024 ./benchmarks/run_exp1b.sh

# symmetry check
./benchmarks/run_bias.sh
```

### Plotting

```sh
python benchmarks/plot_exp1a.py      # speedup, elapsed (reads exp1a_{seq,gpu}.csv)
python benchmarks/plot_exp1b.py [results/exp1b_*.csv]   # density GPU/CPU speedup
```

Figures are written under `benchmarks/results/figures/` (and mirrored into
`report/figures/`). Requires `pandas`, `numpy`, `matplotlib`.

---

# 4. Quick start

```sh
# 1. Build the CPU baseline
cmake -S sequential -B sequential/build -DCMAKE_BUILD_TYPE=Release
cmake --build sequential/build -j

# 2. Watch sand fall in the terminal
./sequential/build/sand_sim --width 80 --height 40 --delay 30

# 3. Time it
./sequential/build/sand_sim --width 512 --height 512 --steps 500 --benchmark

# 4. Paint sand on the GPU
godot --path godot_project           # Space=run, drag=paint, keys 1/2/3/0 pick brush
```
