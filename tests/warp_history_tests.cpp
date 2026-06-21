#include "warp_history.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

contourtty::FlowField uniformFlow(int width, int height, int block_size, double dx, double dy) {
  contourtty::FlowField flow;
  flow.width = width;
  flow.height = height;
  flow.block_size = block_size;
  flow.blocks_x = (width + block_size - 1) / block_size;
  flow.blocks_y = (height + block_size - 1) / block_size;
  flow.vectors.assign(static_cast<std::size_t>(flow.blocks_x) * static_cast<std::size_t>(flow.blocks_y),
                      contourtty::FlowVector{.dx = dx, .dy = dy, .error = 0.0});
  return flow;
}

contourtty::CellLuminanceRegion shapeRegion(double value) {
  return contourtty::CellLuminanceRegion{
    .source = contourtty::SourceRegion{.x0 = 0, .x1 = 1, .y0 = 0, .y1 = 1},
    .values = {value},
  };
}

}  // namespace

int main() {
  const std::vector<char32_t> glyphs{U'A', U'B', U'C'};

  const auto identity = contourtty::warpGlyphHistory(glyphs, 3, 1, uniformFlow(30, 10, 10, 0.0, 0.0));
  expect(identity == glyphs, "zero flow preserves glyph history");

  const auto shifted = contourtty::warpGlyphHistory(glyphs, 3, 1, uniformFlow(30, 10, 10, 10.0, 0.0));
  expect((shifted == std::vector<char32_t>{U'A', U'A', U'B'}), "positive x flow samples previous left cell");

  const std::vector<contourtty::CellLuminanceRegion> shapes{shapeRegion(0.1), shapeRegion(0.2), shapeRegion(0.3)};
  const auto shifted_shapes = contourtty::warpCellShapeHistory(shapes, 3, 1, uniformFlow(30, 10, 10, 10.0, 0.0));
  expect(shifted_shapes.size() == 3, "shape warp preserves count");
  expect(shifted_shapes[0].values == shapes[0].values, "shape warp first cell clamps left");
  expect(shifted_shapes[1].values == shapes[0].values, "shape warp second samples previous left cell");
  expect(shifted_shapes[2].values == shapes[1].values, "shape warp third samples previous middle cell");

  bool mismatch = false;
  try {
    (void)contourtty::warpGlyphHistory(glyphs, 2, 1, uniformFlow(20, 10, 10, 0.0, 0.0));
  } catch (const std::invalid_argument&) {
    mismatch = true;
  }
  expect(mismatch, "warp history rejects glyph count mismatch");

  bool shape_mismatch = false;
  try {
    (void)contourtty::warpCellShapeHistory(shapes, 2, 1, uniformFlow(20, 10, 10, 0.0, 0.0));
  } catch (const std::invalid_argument&) {
    shape_mismatch = true;
  }
  expect(shape_mismatch, "warp history rejects shape count mismatch");
}
