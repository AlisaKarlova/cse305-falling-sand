
#include "simulation.h"
#include "grid.h"

namespace sand {

Simulation::Simulation(std::uint64_t seed)
    : rng_(static_cast<std::mt19937::result_type>(seed))
{}

void Simulation::step(Grid& g) {
    // Alternate column-scan direction per frame to neutralize residual
    // L->R bias.
    const bool reverse_cols = (steps_ & 1u) != 0;

    // we start from the second-to-last row as bottom row has nowhere to fall
    for (int r = g.height() - 2; r >= 0; --r) {
        if (!reverse_cols) {
            for (int c = 0; c < g.width(); ++c) {
                update_sand(g, r, c);
            }
        } else {
            for (int c = g.width() - 1; c >= 0; --c) {
                update_sand(g, r, c);
            }
        }
    }

    ++steps_;
}

bool Simulation::update_sand(Grid& g, int r, int c) {
    // Skip non-sand cells fast. Wood is static; Empty has nothing to do.
    if (g.cell(r, c) != CellType::Sand) return false;
    //straight down
    if (g.at(r + 1, c) == CellType::Empty) {
        g.cell(r + 1, c) = CellType::Sand;
        g.cell(r,     c) = CellType::Empty;
        return true;
    //diagonal
    const bool can_left  = (g.at(r + 1, c - 1) == CellType::Empty);
    const bool can_right = (g.at(r + 1, c + 1) == CellType::Empty);

    int dc;
    if (can_left && can_right) {
        dc = (rng_() & 1u) ? -1 : +1;
    } else if (can_left) {
        dc = -1;
    } else if (can_right) {
        dc = +1;
    } else {
        // Fully blocked, rest in place.
        return false;
    }

    g.cell(r + 1, c + dc) = CellType::Sand;
    g.cell(r,     c)      = CellType::Empty;
    return true;
}

} // namespace sand
}