// =====================================================================
//   The rule for a single sand grain:
//     1. Fall straight down if below is empty.
//     2. Else, if both diagonals are empty, pick one at random.
//     3. Else, if only down-left is empty, go down-left.
//     4. Else, if only down-right is empty, go down-right.
//     5. Else, stay put.
//
//   The naive approach - scan the grid and update each grain in place
//   reading from the same grid we're writing to produces 
//   wrong dynamics. A vertical column of sand falling
//   through empty space remains a rigid rectangle: as we scan bottom-up,
//   each grain finds the cell below empty
//   to fix we use double buffering. Each frame:
//     (a) READ from "current" — the state at the start of the frame.
//     (b) WRITE to "next" — initialized as a copy of "current", so
//         every grain provisionally stays where it is.
//     (c) When a grain decides to move, it claims its destination in
//         "next" and erases its old position in "next". The decision
//         is based purely on "current", so all grains see the same
//         consistent snapshot.
//     (d) After the full sweep, the grid is the new "next".
//
//   CONFLICT RESOLUTION. Two grains in "current" can independently
//   decide to move to the same cell in "next". Concretely, a grain at
//   (r, c-1) choosing down-right and a grain at (r, c+1) choosing
//   down-left both target (r+1, c). 
//   We use "first writer wins": a grain only moves if its destination
//   in "next" is still Empty at write time. If another grain has
//   already claimed it, this grain stays put.

#include "simulation.h"
#include "grid.h"

#include <vector>

namespace sand {

Simulation::Simulation(std::uint64_t seed)
    : rng_(static_cast<std::mt19937::result_type>(seed))
{}

void Simulation::step(Grid& g) {
    const int W = g.width();
    const int H = g.height();

    // Snapshot of the grid at the start of the frame. All decisions
    // are made by reading from this snapshot. This copy is O(W*H) per frame. For a benchmark-
    // grade implementation we'd keep the snapshot as a member and
    // reuse the allocation.
    const std::vector<CellType> current = g.data();
    auto read = [&](int r, int c) -> CellType {
        if (r < 0 || r >= H || c < 0 || c >= W) return CellType::Wood;
        return current[static_cast<std::size_t>(r) * static_cast<std::size_t>(W)
                     + static_cast<std::size_t>(c)];
    };
    auto next_at = [&](int r, int c) -> CellType {
        if (r < 0 || r >= H || c < 0 || c >= W) return CellType::Wood;
        return g.cell(r, c);
    };

    // Alternate column-scan direction per frame. Combined with first-
    // writer-wins conflict resolution, this is what keeps order-induced
    // bias negligible.
    const bool reverse_cols = (steps_ & 1u) != 0;

    for (int r = H - 2; r >= 0; --r) {
        const int c_start = reverse_cols ? W - 1 : 0;
        const int c_end   = reverse_cols ? -1    : W;
        const int c_step  = reverse_cols ? -1    : +1;

        for (int c = c_start; c != c_end; c += c_step) {
            // Decision is made on the start-of-frame snapshot.
            if (read(r, c) != CellType::Sand) continue;

            if (g.cell(r, c) != CellType::Sand) continue;

            // Priority 1: straight down.
            if (read(r + 1, c) == CellType::Empty) {
                // First-writer-wins: has another grain already claimed
                // (r+1, c) in "next"? If so, this grain stays.
                if (next_at(r + 1, c) == CellType::Empty) {
                    g.cell(r + 1, c) = CellType::Sand;
                    g.cell(r,     c) = CellType::Empty;
                }
                continue;
            }

            // Priorities 2-4: diagonals. Evaluate against the snapshot.
            const bool can_left  = (read(r + 1, c - 1) == CellType::Empty);
            const bool can_right = (read(r + 1, c + 1) == CellType::Empty);

            int dc;
            if (can_left && can_right) {
                dc = (rng_() & 1u) ? -1 : +1;
            } else if (can_left) {
                dc = -1;
            } else if (can_right) {
                dc = +1;
            } else {
                continue;
            }

            // First-writer-wins on the chosen diagonal destination.
            if (next_at(r + 1, c + dc) == CellType::Empty) {
                g.cell(r + 1, c + dc) = CellType::Sand;
                g.cell(r,     c)      = CellType::Empty;
            }
            // else: lost the race, stay put
        }
    }

    ++steps_;
}

bool Simulation::update_sand(Grid& /*g*/, int /*r*/, int /*c*/) {
    return false;
}

} // namespace sand