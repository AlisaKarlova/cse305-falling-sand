#include "grid.h"
#include <algorithm>
namespace sand {

Grid::Grid(int width, int height)
    : w_(width),
      h_(height),
      data_(static_cast<std::size_t>(width) * static_cast<std::size_t>(height),
            CellType::Empty)
{}

CellType Grid::at(int row, int col) const {
    // Treat off-grid as immovable wall (Wood)
    if (!in_bounds(row, col)) return CellType::Wood;
    return cell(row, col);
}

void Grid::set(int row, int col, CellType t) {
    if (in_bounds(row, col)) cell(row, col) = t;
}

std::size_t Grid::count(CellType t) const {
    return static_cast<std::size_t>(
        std::count(data_.begin(), data_.end(), t));
}

void Grid::clear() {
    std::fill(data_.begin(), data_.end(), CellType::Empty);
}

void Grid::seed_blob(int row, int col, int radius, CellType t) {
    // Filled disk via the squared-distance test to avoid sqrt
    const int r2 = radius * radius;
    for (int dr = -radius; dr <= radius; ++dr) {
        for (int dc = -radius; dc <= radius; ++dc) {
            if (dr * dr + dc * dc <= r2) {
                set(row + dr, col + dc, t);
            }
        }
    }
}

} // namespace sand
