#pragma once

#include <cstddef>
#include <cstdint>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
enum class ColorPixelFormat {
  Rgb24,
};

// A read-only borrowed color image. The caller keeps data valid and unchanged for
// the complete render call. row_stride_bytes is the byte distance between row starts
// and may exceed the RGB24 row size to represent padding. Source timing remains
// frontend-owned and is intentionally outside this color-only contract.
struct ColorImageView {
  const uint8_t* data = nullptr;
  int width = 0;
  int height = 0;
  std::size_t row_stride_bytes = 0;
  ColorPixelFormat pixel_format = ColorPixelFormat::Rgb24;
};

}  // namespace strok
