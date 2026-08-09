#include "frame_sampling.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <stdexcept>

namespace strok {

Rgb averageRegion(const Frame& frame, int cols, int rows, int col, int row) {
  return averageRegion(colorImageViewFromValidFrame(frame), cols, rows, col, row);
}

Rgb averageRegion(const ColorImageView& image, int cols, int rows, int col, int row) {
  const int x0 = (col * image.width) / cols;
  const int x1 = std::max(x0 + 1, ((col + 1) * image.width) / cols);
  const int y0 = (row * image.height) / rows;
  const int y1 = std::max(y0 + 1, ((row + 1) * image.height) / rows);

  uint64_t r = 0;
  uint64_t g = 0;
  uint64_t b = 0;
  uint64_t count = 0;
  for (int y = y0; y < y1; ++y) {
    for (int x = x0; x < x1; ++x) {
      const Rgb color = colorAt(image, x, y);
      r += color.r;
      g += color.g;
      b += color.b;
      ++count;
    }
  }

  return Rgb{
    .r = static_cast<uint8_t>(r / count),
    .g = static_cast<uint8_t>(g / count),
    .b = static_cast<uint8_t>(b / count),
  };
}

void mirrorFrameHorizontally(Frame& frame) {
  const std::size_t expected = static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h) * 3U;
  if (frame.rgb.size() != expected) {
    throw std::runtime_error("frame rgb buffer size mismatch");
  }
  for (int y = 0; y < frame.h; ++y) {
    for (int x = 0; x < frame.w / 2; ++x) {
      const std::size_t left = (static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(x)) * 3U;
      const std::size_t right = (static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(frame.w - 1 - x)) * 3U;
      std::swap(frame.rgb[left], frame.rgb[right]);
      std::swap(frame.rgb[left + 1], frame.rgb[right + 1]);
      std::swap(frame.rgb[left + 2], frame.rgb[right + 2]);
    }
  }
}

}  // namespace strok
