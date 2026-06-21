#include "lic.hpp"

#include <cstddef>
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

contourtty::GradientField constantGradientField(int width, int height, double gx, double gy) {
  contourtty::GradientField field;
  field.width = width;
  field.height = height;
  field.values.assign(static_cast<std::size_t>(width) * static_cast<std::size_t>(height), contourtty::Gradient{.gx = gx, .gy = gy});
  return field;
}

bool throwsInvalidLength() {
  try {
    const auto field = constantGradientField(2, 2, 1.0, 0.0);
    (void)contourtty::licValueForCell(field, 2, 2, 0, 0, 0);
  } catch (const std::invalid_argument&) {
    return true;
  }
  return false;
}

}  // namespace

int main() {
  const double noise = contourtty::licNoiseSample(4, 7, 11);
  expect(noise >= 0.0 && noise <= 1.0, "noise sample is normalized");
  expect(contourtty::licNoiseSample(4, 7, 11) == noise, "noise sample is deterministic");

  const auto field = constantGradientField(8, 8, 1.0, 0.0);
  const double value = contourtty::licValueForCell(field, 4, 4, 1, 1, 4, 17);
  expect(value >= 0.0 && value <= 1.0, "LIC value is normalized");
  expect(contourtty::licValueForCell(field, 4, 4, 1, 1, 4, 17) == value, "LIC trace is deterministic");

  contourtty::CellGradient gradient{.gx = 1.0, .gy = 0.0, .magnitude = 1.0, .orientation = 0.0};
  expect(contourtty::licGlyphForCell(gradient, 0.1, 0.0, 0.0) == U'│', "horizontal gradient maps to vertical flow glyph");
  expect(contourtty::licGlyphForCell(gradient, 0.1, 1.0, 1.0) == U' ', "bright high-noise cell stays blank");
  expect(contourtty::licGlyphForCell(contourtty::CellGradient{}, 0.1, 0.0, 0.0) == U'•', "flat dark cell maps to dot");

  contourtty::CellBuffer cells(4, 4);
  for (contourtty::Cell& cell : cells.cells()) {
    cell.fg = contourtty::Rgb{.r = 0, .g = 0, .b = 0};
  }
  contourtty::applyLicFlow(&cells, field, 4, 4, 4, 0.1, 17);
  expect(cells.at(1, 1).glyph == U'│', "applyLicFlow writes flow-oriented glyph");
  expect(throwsInvalidLength(), "LIC rejects non-positive length");
}
