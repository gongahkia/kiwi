#pragma once

#include <cstddef>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
enum class DepthPixelFormat {
  Float64,
};

enum class DepthInterpretation {
  CameraLinear,
};

// A read-only borrowed depth image. The caller keeps data valid and unchanged for
// the complete render call. Float64 values are camera-linear, are not normalized,
// and use an application-defined unit; only finite relative ordering is consumed,
// with larger values representing farther samples. NaN and infinities are invalid
// samples. An absent DepthImageView leaves RGB-only reconstruction unchanged.
struct DepthImageView {
  const double* data = nullptr;
  int width = 0;
  int height = 0;
  std::size_t row_stride_bytes = 0;
  DepthPixelFormat pixel_format = DepthPixelFormat::Float64;
  DepthInterpretation interpretation = DepthInterpretation::CameraLinear;
};

}  // namespace strok
