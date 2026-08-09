#pragma once

#include <cstddef>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
enum class NormalPixelFormat {
  Float64x3,
};

enum class NormalSpace {
  View,
};

// A read-only borrowed normal image. The caller keeps data valid and unchanged for
// the complete render call. Float64x3 stores x, y, z consecutively for each pixel in
// view space: +x is right, +y is up, and +z faces the viewer. Samples may be non-unit;
// the renderer normalizes finite nonzero vectors. Zero-length or non-finite samples use
// a neutral view-facing normal. An absent NormalImageView leaves RGB-only reconstruction
// unchanged.
struct NormalImageView {
  const double* data = nullptr;
  int width = 0;
  int height = 0;
  std::size_t row_stride_bytes = 0;
  NormalPixelFormat pixel_format = NormalPixelFormat::Float64x3;
  NormalSpace space = NormalSpace::View;
};

}  // namespace strok
