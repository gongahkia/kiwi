#pragma once

namespace contourtty {

struct GraphicsAlignment {
  int cols = 0;
  int rows = 0;
  int pixel_width = 0;
  int pixel_height = 0;
  int cell_pixel_width = 0;
  int cell_pixel_height = 0;
};

GraphicsAlignment graphicsAlignmentForRaster(int cols, int rows, int pixel_width, int pixel_height);
int cellLeftPixel(const GraphicsAlignment& alignment, int col);
int cellTopPixel(const GraphicsAlignment& alignment, int row);
bool pixelAlignedToCellColumn(const GraphicsAlignment& alignment, int col, int pixel_x, int tolerance_px = 1);

}  // namespace contourtty
