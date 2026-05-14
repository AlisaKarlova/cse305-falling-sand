
//   * Row-major std::vector<CellType>: contiguous memory, cache-friendly
//     for the inner column loop, and trivial to mirror as an SSBO on the
//     GPU side later.
//   * Out-of-bounds reads return Wood (= "immovable"). This means the
//   * (row, col) ordering throughout. Row 0 is the top, sand falls in
//     the +row direction.
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace sand {

enum class CellType : std::uint8_t {
    Empty = 0,
    Sand  = 1,
    Wood  = 2,
};

class Grid {
public:
    Grid(int width, int height);

    int width()  const { return w_; }
    int height() const { return h_; }

    // Bounds-checked accessors. at() returns Wood for out-of-bounds reads
    // (see header comment); set() silently ignores out-of-bounds writes.
    CellType at(int row, int col) const;
    void     set(int row, int col, CellType t);

    // Fast unchecked accessors for the inner update loop. The caller is
    // responsible for bounds; we deliberately keep them inlined.
    CellType& cell(int row, int col)       { return data_[index(row, col)]; }
    CellType  cell(int row, int col) const { return data_[index(row, col)]; }

    bool in_bounds(int row, int col) const {
        return row >= 0 && row < h_ && col >= 0 && col < w_;
    }

    // Conservation invariant helper: count cells of a given type.
    std::size_t count(CellType t) const;

    void clear();

    // Stamp a filled disk of cells of the given type, centred at (row, col).
    // Used to set up an initial scene
    void seed_blob(int row, int col, int radius, CellType t);

    // Read-only access to the raw buffer (used by the renderer).
    const std::vector<CellType>& data() const { return data_; }

private:
    std::size_t index(int row, int col) const {
        return static_cast<std::size_t>(row) * static_cast<std::size_t>(w_)
             + static_cast<std::size_t>(col);
    }

    int w_;
    int h_;
    std::vector<CellType> data_;
};

} // namespace sand
