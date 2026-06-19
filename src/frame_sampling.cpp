#include "frame_sampling.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>

namespace contourtty {

Rgb averageRegion(const Frame& frame, int cols, int rows, int col, int row) {
  const int x0 = (col * frame.w) / cols;
  const int x1 = std::max(x0 + 1, ((col + 1) * frame.w) / cols);
  const int y0 = (row * frame.h) / rows;
  const int y1 = std::max(y0 + 1, ((row + 1) * frame.h) / rows);

  uint64_t r = 0;
  uint64_t g = 0;
  uint64_t b = 0;
  uint64_t count = 0;
  for (int y = y0; y < y1; ++y) {
    for (int x = x0; x < x1; ++x) {
      const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(x)) * 3;
      r += frame.rgb[index];
      g += frame.rgb[index + 1];
      b += frame.rgb[index + 2];
      ++count;
    }
  }

  return Rgb{
    .r = static_cast<uint8_t>(r / count),
    .g = static_cast<uint8_t>(g / count),
    .b = static_cast<uint8_t>(b / count),
  };
}

}  // namespace contourtty
