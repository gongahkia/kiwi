#include "graphics_alignment.hpp"

#include <cstdlib>
#include <stdexcept>

namespace contourtty {

GraphicsAlignment graphicsAlignmentForRaster(int cols, int rows, int pixel_width, int pixel_height) {
  if (cols <= 0 || rows <= 0 || pixel_width <= 0 || pixel_height <= 0) {
    throw std::invalid_argument("graphics alignment dimensions must be positive");
  }
  if (pixel_width % cols != 0 || pixel_height % rows != 0) {
    throw std::invalid_argument("graphics raster dimensions must align to terminal cells");
  }
  return GraphicsAlignment{
    .cols = cols,
    .rows = rows,
    .pixel_width = pixel_width,
    .pixel_height = pixel_height,
    .cell_pixel_width = pixel_width / cols,
    .cell_pixel_height = pixel_height / rows,
  };
}

int cellLeftPixel(const GraphicsAlignment& alignment, int col) {
  if (col < 0 || col > alignment.cols) {
    throw std::out_of_range("cell column outside graphics alignment");
  }
  return col * alignment.cell_pixel_width;
}

int cellTopPixel(const GraphicsAlignment& alignment, int row) {
  if (row < 0 || row > alignment.rows) {
    throw std::out_of_range("cell row outside graphics alignment");
  }
  return row * alignment.cell_pixel_height;
}

bool pixelAlignedToCellColumn(const GraphicsAlignment& alignment, int col, int pixel_x, int tolerance_px) {
  if (tolerance_px < 0) {
    throw std::invalid_argument("alignment tolerance cannot be negative");
  }
  return std::abs(pixel_x - cellLeftPixel(alignment, col)) <= tolerance_px;
}

}  // namespace contourtty
