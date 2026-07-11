#include "graphics_alignment.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  {
    const auto alignment = strok::graphicsAlignmentForRaster(80, 24, 640, 288);
    expect(alignment.cell_pixel_width == 8, "cell pixel width");
    expect(alignment.cell_pixel_height == 12, "cell pixel height");
    expect(strok::cellLeftPixel(alignment, 0) == 0, "first column boundary");
    expect(strok::cellLeftPixel(alignment, 80) == 640, "last column boundary");
    expect(strok::cellTopPixel(alignment, 24) == 288, "last row boundary");
    expect(strok::pixelAlignedToCellColumn(alignment, 12, 96), "exact column alignment");
    expect(strok::pixelAlignedToCellColumn(alignment, 12, 97), "one pixel tolerance alignment");
    expect(!strok::pixelAlignedToCellColumn(alignment, 12, 98), "outside tolerance alignment");
  }

  {
    bool threw = false;
    try {
      (void)strok::graphicsAlignmentForRaster(80, 24, 641, 288);
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "unaligned raster width rejected");
  }

  {
    const auto alignment = strok::graphicsAlignmentForRaster(2, 2, 16, 24);
    bool threw = false;
    try {
      (void)strok::cellLeftPixel(alignment, 3);
    } catch (const std::out_of_range&) {
      threw = true;
    }
    expect(threw, "out of range column rejected");
  }
}
