#include "warp_history.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <stdexcept>

namespace strok {
namespace {

void validateWarpInputs(std::size_t count, int cols, int rows, const FlowField& flow, const char* label) {
  if (cols <= 0 || rows <= 0) {
    throw std::invalid_argument("warp history dimensions must be positive");
  }
  if (count != static_cast<std::size_t>(cols) * static_cast<std::size_t>(rows)) {
    throw std::invalid_argument(label);
  }
  if (flow.width <= 0 || flow.height <= 0 || flow.block_size <= 0 ||
      flow.blocks_x <= 0 || flow.blocks_y <= 0 ||
      flow.vectors.size() != static_cast<std::size_t>(flow.blocks_x) * static_cast<std::size_t>(flow.blocks_y)) {
    throw std::invalid_argument("invalid flow field");
  }
}

std::size_t warpedSourceIndex(int col, int row, int cols, int rows, const FlowField& flow) {
  const double cell_width = static_cast<double>(flow.width) / static_cast<double>(cols);
  const double cell_height = static_cast<double>(flow.height) / static_cast<double>(rows);
  const double pixel_x = (static_cast<double>(col) + 0.5) * cell_width;
  const double pixel_y = (static_cast<double>(row) + 0.5) * cell_height;
  const int block_x = std::clamp(static_cast<int>(pixel_x / static_cast<double>(flow.block_size)), 0, flow.blocks_x - 1);
  const int block_y = std::clamp(static_cast<int>(pixel_y / static_cast<double>(flow.block_size)), 0, flow.blocks_y - 1);
  const FlowVector vector = flow.at(block_x, block_y);
  const double previous_x = pixel_x - vector.dx;
  const double previous_y = pixel_y - vector.dy;
  const int previous_col = std::clamp(static_cast<int>(std::floor(previous_x / cell_width)), 0, cols - 1);
  const int previous_row = std::clamp(static_cast<int>(std::floor(previous_y / cell_height)), 0, rows - 1);
  return static_cast<std::size_t>(previous_row) * static_cast<std::size_t>(cols) + static_cast<std::size_t>(previous_col);
}

}  // namespace

std::vector<char32_t> warpGlyphHistory(std::span<const char32_t> previous_glyphs, int cols, int rows, const FlowField& flow) {
  validateWarpInputs(previous_glyphs.size(), cols, rows, flow, "warp history glyph count mismatch");

  std::vector<char32_t> warped(previous_glyphs.size(), U' ');
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      warped[static_cast<std::size_t>(row) * static_cast<std::size_t>(cols) + static_cast<std::size_t>(col)] =
        previous_glyphs[warpedSourceIndex(col, row, cols, rows, flow)];
    }
  }
  return warped;
}

std::vector<CellLuminanceRegion> warpCellShapeHistory(std::span<const CellLuminanceRegion> previous_shapes, int cols, int rows, const FlowField& flow) {
  validateWarpInputs(previous_shapes.size(), cols, rows, flow, "warp history shape count mismatch");

  std::vector<CellLuminanceRegion> warped(previous_shapes.size());
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      warped[static_cast<std::size_t>(row) * static_cast<std::size_t>(cols) + static_cast<std::size_t>(col)] =
        previous_shapes[warpedSourceIndex(col, row, cols, rows, flow)];
    }
  }
  return warped;
}

std::vector<Cell> warpCellHistory(std::span<const Cell> previous_cells, int cols, int rows, const FlowField& flow) {
  validateWarpInputs(previous_cells.size(), cols, rows, flow, "warp history cell count mismatch");

  std::vector<Cell> warped(previous_cells.size());
  for (int row = 0; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      warped[static_cast<std::size_t>(row) * static_cast<std::size_t>(cols) + static_cast<std::size_t>(col)] =
        previous_cells[warpedSourceIndex(col, row, cols, rows, flow)];
    }
  }
  return warped;
}

}  // namespace strok
