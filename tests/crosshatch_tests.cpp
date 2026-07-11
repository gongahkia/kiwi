#include "crosshatch.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::CellGradient gradient(double gx, double gy) {
  return strok::CellGradient{
    .gx = gx,
    .gy = gy,
    .magnitude = std::hypot(gx, gy),
    .orientation = std::atan2(gy, gx),
    .horizontal_energy = std::abs(gx),
    .vertical_energy = std::abs(gy),
  };
}

}  // namespace

int main() {
  {
    const auto glyph = strok::crosshatchGlyphForCell(gradient(1.0, 0.0), 0.1, 0.8, 0, 0);
    expect(glyph == U'│', "vertical edge hatches vertical");
  }

  {
    const auto glyph = strok::crosshatchGlyphForCell(gradient(0.0, 1.0), 0.1, 0.8, 0, 0);
    expect(glyph == U'─', "horizontal edge hatches horizontal");
  }

  {
    const auto glyph = strok::crosshatchGlyphForCell(gradient(1.0, 1.0), 0.1, 0.8, 0, 0);
    expect(glyph == U'╱', "positive diagonal hatches slash");
  }

  {
    const auto glyph = strok::crosshatchGlyphForCell(gradient(1.0, -1.0), 0.1, 0.8, 0, 0);
    expect(glyph == U'╲', "negative diagonal hatches backslash");
  }

  {
    const auto glyph = strok::crosshatchGlyphForCell(strok::CellGradient{}, 0.1, 0.1, 0, 0);
    expect(glyph == U'╳', "dark flat cell gets dense crosshatch");
  }

  {
    strok::CellBuffer cells(1, 1);
    cells.at(0, 0).fg = strok::Rgb{.r = 20, .g = 20, .b = 20};
    strok::GradientField gradients;
    gradients.width = 1;
    gradients.height = 1;
    gradients.values = {strok::Gradient{.gx = 1.0, .gy = 0.0}};
    strok::applyCrosshatch(&cells, gradients, 1, 1, 0.1);
    expect(cells.at(0, 0).glyph == U'╳', "applyCrosshatch writes dense dark glyph");
  }
}
