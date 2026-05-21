#pragma once

#include <cstdint>

namespace sand {

struct ViewerArgs {
    int           width  = 200;
    int           height = 200;
    std::uint64_t seed   = 0xC5E305ULL;
};

// Opens an SDL2 window and runs the interactive viewer.
// Returns 0 on clean exit, non-zero on SDL initialisation failure.
int run_viewer(const ViewerArgs& a);

} // namespace sand