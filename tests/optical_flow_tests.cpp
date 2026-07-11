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

strok::LuminanceField texturedField(int width, int height) {
  strok::LuminanceField field;
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

strok::LuminanceField shiftedField(const strok::LuminanceField& source, int dx, int dy) {
  strok::LuminanceField shifted;
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
  const strok::LuminanceField still = texturedField(32, 32);
  const strok::FlowField static_flow = strok::computeBlockOpticalFlow(still, still, 8, 4);
  expect(static_flow.blocks_x == 4 && static_flow.blocks_y == 4, "flow dimensions");
  for (const strok::FlowVector vector : static_flow.vectors) {
    expect(vector.dx == 0.0 && vector.dy == 0.0, "static flow is zero");
  }

  const strok::LuminanceField current = shiftedField(still, 2, 1);
  const strok::FlowField flow = strok::computeBlockOpticalFlow(still, current, 8, 4);
  const strok::FlowVector center = flow.at(1, 1);
  expect(center.dx == 2.0 && center.dy == 1.0, "translated block flow matches shift");
  expect(std::isfinite(center.error), "flow error is finite");
}
