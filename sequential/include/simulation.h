
// The class owns its RNG so simulations are deterministic given a seed
#pragma once

#include <cstdint>
#include <random>

namespace sand {

class Grid;

class Simulation {
public:
    explicit Simulation(std::uint64_t seed = 0xC5E305ULL);


    void step(Grid& g);

    std::uint64_t step_count() const { return steps_; }

private:
    // Try to update a single sand cell at (r, c). Returns true if the
    // grain moved. Pulled out of step() to compare against the GPU shader's logic later.
    bool update_sand(Grid& g, int r, int c);

    std::mt19937   rng_;
    std::uint64_t  steps_ = 0;
};

} // namespace sand
