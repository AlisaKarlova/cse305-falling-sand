# CSE305 Project — Falling Sand Simulation

A cellular-automaton sand simulation in two implementations:
1. A sequential C++ CPU baseline, and
2. A parallel GPU implementation using Godot 4 compute shaders.


## Repository layout

```
sequential/        C++ baseline (built and benchmarked)
godot_project/     Godot 4 project with compute shaders 
benchmarks/        Sweep scripts and result CSVs
report/           
```

## Sequential baseline

### Build

```sh
cmake -S sequential -B sequential/build -DCMAKE_BUILD_TYPE=Release
cmake --build sequential/build -j
```

The binary is `sequential/build/sand_sim`. Do not benchmark Debug builds — the timing numbers are meaningless.

### Run

Interactive ANSI-terminal animation (default 200×200, ~60 fps):
```sh
./sequential/build/sand_sim
```

Smaller, slower, easier to watch:
```sh
./sequential/build/sand_sim --width 80 --height 40 --steps 600 --delay 30
```

Benchmark mode:
```sh
./sequential/build/sand_sim --width 512 --height 512 --steps 500 --benchmark
```

See `./sequential/build/sand_sim --help` for the full flag list.

## Benchmarks

Sweep the sequential baseline across grid sizes and write a CSV to `benchmarks/results/`:

```sh
./benchmarks/run_seq.sh
```