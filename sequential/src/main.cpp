

//comments and formatting in this file is done with Claude to keep the code readable and clean
// main.cpp — Driver. CLI parsing, scene seeding, two run modes:
//
//   --benchmark : no rendering, no sleep. Time N steps end-to-end and
//                 print a single CSV-ish line. This is what the
//                 benchmarks/ scripts will parse.
//
//   (default)   : interactive ANSI-terminal animation. Useful for
//                 sanity-checking the physics. Not "the product" — just
//                 a zero-dependency way to see grains fall.
//
// We deliberately avoid SDL/Godot/etc. here: this binary is the pure
// C++ baseline. The Godot project handles real rendering for the GPU
// version.
// =====================================================================

#ifdef ENABLE_VIEWER
#include "viewer.h"
#endif

#include "grid.h"
#include "simulation.h"

#include <iostream>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

namespace {

struct Args {
    int           width            = 200;
    int           height           = 200;
    int           steps            = 1000;
    bool          benchmark        = false;
    bool          viewer           = false;
    int           render_interval  = 1;   // frames between renders
    int           delay_ms         = 16;  // ~60 fps in interactive mode
    std::uint64_t seed             = 0xC5E305ULL;
    int           warmup_steps     = 5;  
    double        fill             = 0.0;   // 0 = blob scene; >0 = random fill at this density
    bool          bias             = false;

};

// Benchmark scene: the same three sand blobs as seed_initial() but with NO
// wood. The GPU (Margolus) implementation only models sand/empty, so dropping
// wood here lets both benchmarks seed a byte-identical initial state and be
// compared fairly. Blob positions/radii are kept identical to seed_initial so
// the timed workload matches the interactive demo's sand layout.
void seed_benchmark(sand::Grid& g) {
    const int small_dim = std::min(g.width(), g.height());
    g.seed_blob(g.height() / 6,        g.width() / 2,     small_dim / 16,
                sand::CellType::Sand);
    g.seed_blob(g.height() / 4,        g.width() / 3,     small_dim / 24,
                sand::CellType::Sand);
    g.seed_blob(g.height() / 4,        2 * g.width() / 3, small_dim / 24,
                sand::CellType::Sand);
}

// Random Bernoulli fill at target density. Each cell is set to Sand with
// probability `fraction` independently. Uses std::mt19937_64 (period 2^19937-1,
// passes all standard statistical tests) — no hand-rolled RNG, no bit-truncation
// pitfalls. Reproducible given the same seed.
void seed_random(sand::Grid& g, double fraction, std::uint64_t seed) {

    const double f = std::max(0.0, std::min(fraction, 1.0)); // same as:    const double f = std::clamp(fraction, 0.0, 1.0);
    if (f <= 0.0) return;

    std::mt19937_64 rng(seed);
    std::bernoulli_distribution coin(f);

    for (int r = 0; r < g.height(); ++r) {
        for (int c = 0; c < g.width(); ++c) {
            if (coin(rng)) {
                g.set(r, c, sand::CellType::Sand);
            }
        }
    }
}
// terminal renderer, done with Claude code to easier check the simulations visually


void print_usage(const char* prog) {
    std::fprintf(stderr,
        "Usage: %s [options]\n"
        "  --width  N        grid width  (default 200)\n"
        "  --height N        grid height (default 200)\n"
        "  --steps  N        number of simulation steps (default 1000)\n"
        "  --benchmark       no rendering, just time the steps\n"
        "  --viewer          interactive SDL2 window (requires ENABLE_VIEWER build)\n"
        "  --warmup N        warmup steps before benchmark timing (default 5)\n"
        "  --seed   N        RNG seed (default 0xC5E305)\n"
        "  --delay  MS       per-frame sleep in interactive mode (default 16)\n"
        "  --fill   F        random Bernoulli fill at density F in [0,1]; overrides blob scene\n"
        "  --bias            symmetry test: single centered blob, count L vs R\n"
        "  -h, --help        show this message\n",
        prog);
}

// Tiny hand-rolled CLI parser
bool parse_args(int argc, char** argv, Args& out) {
    auto need_value = [&](int& i, const char* name) -> const char* {
        if (i + 1 >= argc) {
            std::fprintf(stderr, "error: %s needs a value\n", name);
            return nullptr;
        }
        return argv[++i];
    };

    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "-h" || a == "--help") { print_usage(argv[0]); return false; }
        else if (a == "--benchmark") { out.benchmark = true; }
        else if (a == "--viewer")    { out.viewer    = true; }
        else if (a == "--width")  { auto v = need_value(i, "--width");  if (!v) return false; out.width  = std::atoi(v); }
        else if (a == "--height") { auto v = need_value(i, "--height"); if (!v) return false; out.height = std::atoi(v); }
        else if (a == "--steps")  { auto v = need_value(i, "--steps");  if (!v) return false; out.steps  = std::atoi(v); }
        else if (a == "--warmup") { auto v = need_value(i, "--warmup"); if (!v) return false; out.warmup_steps = std::atoi(v); }
        else if (a == "--seed")   { auto v = need_value(i, "--seed");   if (!v) return false; out.seed   = std::strtoull(v, nullptr, 0); }
        else if (a == "--delay")  { auto v = need_value(i, "--delay");  if (!v) return false; out.delay_ms = std::atoi(v); }
        else if (a == "--fill")   { auto v = need_value(i, "--fill");   if (!v) return false; out.fill = std::atof(v); }
        else if (a == "--bias")   { out.bias = true; }
        else {
            std::fprintf(stderr, "unknown argument: %s\n", a.c_str());
            print_usage(argv[0]);
            return false;
        }
    }

    if (out.width <= 0 || out.height <= 0) {
        std::fprintf(stderr, "error: --width and --height must be > 0\n");
        return false;
    }
    if (out.steps < 0) {
        std::fprintf(stderr, "error: --steps must be >= 0\n");
        return false;
    }
    return true;
}

// Lay down a small scene: a couple of sand blobs over a wood platform
// with a gap. Enough to exercise straight-fall, diagonal-fall, and
// collision-with-static-obstacle in a single run.
void seed_initial(sand::Grid& g) {
    const int small_dim = std::min(g.width(), g.height());

    // Three blobs of sand near the top, slightly off-centre.
    g.seed_blob(g.height() / 6,        g.width() / 2,     small_dim / 16,
                sand::CellType::Sand);
    g.seed_blob(g.height() / 4,        g.width() / 3,     small_dim / 24,
                sand::CellType::Sand);
    g.seed_blob(g.height() / 4,        2 * g.width() / 3, small_dim / 24,
                sand::CellType::Sand);

    // Wood platform with a gap in the middle so sand can pass through.
    const int floor_row = 3 * g.height() / 4;
    //const int gap_l     = g.width() * 2 / 5;
    //const int gap_r     = g.width() * 3 / 5;
    const int gap_half  = small_dim / 32;   // ~6 cells; blob diameter is small_dim/8 (~25)
    const int gap_l     = g.width() / 2 - gap_half;
    const int gap_r     = g.width() / 2 + gap_half;
    for (int c = g.width() / 8; c < 7 * g.width() / 8; ++c) {
        if (c >= gap_l && c < gap_r) continue;
        g.set(floor_row, c, sand::CellType::Wood);
    }
}

// Single sand blob centered on the vertical midline, dropped from row H/4.
// Used by run_bias().
void seed_single_blob(sand::Grid& g) {
    const int small_dim = std::min(g.width(), g.height());
    g.seed_blob(g.height() / 4, g.width() / 2, small_dim / 16,
                sand::CellType::Sand);
}


// terminal renderer, done with Claude code to easier check the simulations visually
void render_terminal(const sand::Grid& g) {
    std::fputs("\x1b[H", stdout);  // move cursor to top-left

    std::string line;
    line.reserve(static_cast<std::size_t>(g.width()) + 1);
    for (int r = 0; r < g.height(); ++r) {
        line.clear();
        for (int c = 0; c < g.width(); ++c) {
            switch (g.cell(r, c)) {
                case sand::CellType::Empty: line.push_back(' '); break;
                case sand::CellType::Sand:  line.push_back('.'); break;
                case sand::CellType::Wood:  line.push_back('#'); break;
            }
        }
        line.push_back('\n');
        std::fputs(line.c_str(), stdout);
    }
    std::fflush(stdout);
}

int run_benchmark(const Args& a) {
    sand::Grid       g(a.width, a.height);
    if (a.fill > 0.0) {
        seed_random(g, a.fill, a.seed);
    } else {
        seed_benchmark(g);
    }
    sand::Simulation sim(a.seed);   

    const std::size_t initial_sand = g.count(sand::CellType::Sand);
    const std::size_t initial_wood = g.count(sand::CellType::Wood);

    // Warmup
    for (int i = 0; i < a.warmup_steps; ++i) sim.step(g);

    using clk = std::chrono::high_resolution_clock;
    const auto t0 = clk::now();
    for (int i = 0; i < a.steps; ++i) sim.step(g);
    const auto t1 = clk::now();

    const double elapsed_s = std::chrono::duration<double>(t1 - t0).count();
    const double cell_updates =
        static_cast<double>(a.width) *
        static_cast<double>(a.height) *
        static_cast<double>(a.steps);
    const double cell_updates_per_s =
        elapsed_s > 0.0 ? (cell_updates / elapsed_s) : 0.0;

    const std::size_t final_sand = g.count(sand::CellType::Sand);
    const std::size_t final_wood = g.count(sand::CellType::Wood);

    // One line, key=value pairs. Easy to grep/awk in benchmarks/.
    std::printf("BENCH width=%d height=%d steps=%d warmup=%d "
                "elapsed_s=%.6f cell_updates_per_s=%.3e "
                "sand_initial=%zu sand_final=%zu "
                "wood_initial=%zu wood_final=%zu\n",
                a.width, a.height, a.steps, a.warmup_steps,
                elapsed_s, cell_updates_per_s,
                initial_sand, final_sand,
                initial_wood, final_wood);

    // Fail loudly on conservation violation so CI catches regressions.
    if (initial_sand != final_sand || initial_wood != final_wood) {
        std::fprintf(stderr,
            "CONSERVATION VIOLATION: sand %zu -> %zu, wood %zu -> %zu\n",
            initial_sand, final_sand, initial_wood, final_wood);
        return 2;
    }
    return 0;
}

// Symmetry experiment. Seeds a single centered blob, runs N steps, counts
// sand in the strict left half (cols 0..W/2-1) and strict right half
// (cols W/2+1..W-1). Center column excluded from both halves so the
// partition itself is invariant under reflection about col W/2.
int run_bias(const Args& a) {
    sand::Grid       g(a.width, a.height);
    seed_single_blob(g);
    sand::Simulation sim(a.seed);

    auto count_halves = [&](std::size_t& L, std::size_t& R) {
        L = 0; R = 0;
        const int cmid = a.width / 2;
        for (int r = 0; r < a.height; ++r) {
            for (int c = 0; c < a.width; ++c) {
                if (g.cell(r, c) != sand::CellType::Sand) continue;
                if      (c < cmid) ++L;
                else if (c > cmid) ++R;
            }
        }
    };

    const std::size_t initial_sand = g.count(sand::CellType::Sand);

    // Sanity: the seed itself must be perfectly symmetric.
    std::size_t L0 = 0, R0 = 0;
    count_halves(L0, R0);
    if (L0 != R0) {
        std::fprintf(stderr, "FATAL: initial seed asymmetric: L0=%zu R0=%zu\n",
                     L0, R0);
        return 2;
    }

    for (int i = 0; i < a.steps; ++i) sim.step(g);

    const std::size_t final_sand = g.count(sand::CellType::Sand);
    if (initial_sand != final_sand) {
        std::fprintf(stderr, "CONSERVATION VIOLATION: sand %zu -> %zu\n",
                     initial_sand, final_sand);
        return 2;
    }

    std::size_t L = 0, R = 0;
    count_halves(L, R);
    const double rel_diff = final_sand > 0
        ? static_cast<double>(static_cast<long long>(L) - static_cast<long long>(R))
          / static_cast<double>(final_sand)
        : 0.0;

    std::printf("BIAS impl=seq width=%d height=%d steps=%d "
                "left=%zu right=%zu total=%zu rel_diff=%.6f\n",
                a.width, a.height, a.steps, L, R, final_sand, rel_diff);
    return 0;
}


int run_interactive(const Args& a) {
    sand::Grid       g(a.width, a.height);
    seed_initial(g);
    sand::Simulation sim(a.seed);

    const std::size_t initial_sand = g.count(sand::CellType::Sand);

    std::fputs("\x1b[2J", stdout);  // clear screen once on entry
    for (int i = 0; i < a.steps; ++i) {
        sim.step(g);
        if (a.render_interval <= 0 || (i % a.render_interval == 0)) {
            render_terminal(g);
            if (a.delay_ms > 0) {
                std::this_thread::sleep_for(
                    std::chrono::milliseconds(a.delay_ms));
            }
        }
    }
    render_terminal(g);

    const std::size_t final_sand = g.count(sand::CellType::Sand);
    if (initial_sand != final_sand) {
        std::fprintf(stderr,
            "CONSERVATION VIOLATION: sand %zu -> %zu\n",
            initial_sand, final_sand);
        return 2;
    }
    return 0;
}

} // namespace

int main(int argc, char** argv) {
    Args a;
    if (!parse_args(argc, argv, a)) return 1;

    if (a.viewer) {
#ifdef ENABLE_VIEWER
        sand::ViewerArgs va;
        va.width  = a.width;
        va.height = a.height;
        va.seed   = a.seed;
        return sand::run_viewer(va);
#else
        std::fprintf(stderr,
            "error: --viewer requires building with -DENABLE_VIEWER=ON\n");
        return 1;
#endif
    }
    if (a.bias) return run_bias(a);
    return a.benchmark ? run_benchmark(a) : run_interactive(a);
}
