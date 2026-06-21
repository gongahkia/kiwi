#include "optical_flow.hpp"

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

contourtty::LuminanceField texturedField(int width, int height) {
  contourtty::LuminanceField field;
  field.width = width;
  field.height = height;
  field.values.reserve(static_cast<std::size_t>(width) * static_cast<std::size_t>(height));
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      field.values.push_back(static_cast<double>((x * 13 + y * 7 + x * y * 3) % 251) / 250.0);
    }
  }
  return field;
}

contourtty::LuminanceField shiftedField(const contourtty::LuminanceField& source, int dx, int dy) {
  contourtty::LuminanceField shifted;
  shifted.width = source.width;
  shifted.height = source.height;
  shifted.values.assign(source.values.size(), 0.0);
  for (int y = 0; y < source.height; ++y) {
    for (int x = 0; x < source.width; ++x) {
      const int sx = x - dx;
      const int sy = y - dy;
      if (sx >= 0 && sy >= 0 && sx < source.width && sy < source.height) {
        shifted.values[static_cast<std::size_t>(y) * static_cast<std::size_t>(source.width) + static_cast<std::size_t>(x)] =
          source.values[static_cast<std::size_t>(sy) * static_cast<std::size_t>(source.width) + static_cast<std::size_t>(sx)];
      }
    }
  }
  return shifted;
}

}  // namespace

int main() {
  const contourtty::LuminanceField still = texturedField(32, 32);
  const contourtty::FlowField static_flow = contourtty::computeBlockOpticalFlow(still, still, 8, 4);
  expect(static_flow.blocks_x == 4 && static_flow.blocks_y == 4, "flow dimensions");
  for (const contourtty::FlowVector vector : static_flow.vectors) {
    expect(vector.dx == 0.0 && vector.dy == 0.0, "static flow is zero");
  }

  const contourtty::LuminanceField current = shiftedField(still, 2, 1);
  const contourtty::FlowField flow = contourtty::computeBlockOpticalFlow(still, current, 8, 4);
  const contourtty::FlowVector center = flow.at(1, 1);
  expect(center.dx == 2.0 && center.dy == 1.0, "translated block flow matches shift");
  expect(std::isfinite(center.error), "flow error is finite");
}
