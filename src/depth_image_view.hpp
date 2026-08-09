#pragma once

#include "../include/strok/depth_image_view.hpp"

#include <cmath>
#include <cstddef>
#include <cstring>
#include <limits>
#include <optional>
#include <string>

namespace strok {

inline bool depthSampleValid(double depth) noexcept {
  return std::isfinite(depth);
}

inline std::optional<std::string> depthImageViewError(const DepthImageView& image) {
  if (image.data == nullptr) {
    return "depth image data is required";
  }
  if (image.width <= 0 || image.height <= 0) {
    return "depth image dimensions must be positive";
  }
  if (image.pixel_format != DepthPixelFormat::Float64) {
    return "depth image pixel format is unsupported";
  }
  if (image.interpretation != DepthInterpretation::CameraLinear) {
    return "depth image interpretation is unsupported";
  }
  if (image.row_stride_bytes % sizeof(double) != 0U) {
    return "depth image row stride must preserve Float64 alignment";
  }

  const std::size_t width = static_cast<std::size_t>(image.width);
  const std::size_t height = static_cast<std::size_t>(image.height);
  if (width > std::numeric_limits<std::size_t>::max() / height) {
    return "depth image dimensions overflow";
  }
  if (width > std::numeric_limits<std::size_t>::max() / sizeof(double)) {
    return "depth image row size overflows";
  }
  const std::size_t row_bytes = width * sizeof(double);
  if (image.row_stride_bytes < row_bytes) {
    return "depth image row stride is smaller than Float64 row size";
  }

  const std::size_t rows_before_last = height - 1U;
  if (rows_before_last > 0 && image.row_stride_bytes > (std::numeric_limits<std::size_t>::max() - row_bytes) / rows_before_last) {
    return "depth image layout overflows";
  }
  return std::nullopt;
}

inline double depthAt(const DepthImageView& image, int x, int y) noexcept {
  const auto* row = reinterpret_cast<const unsigned char*>(image.data) + static_cast<std::size_t>(y) * image.row_stride_bytes;
  double depth = 0.0;
  std::memcpy(&depth, row + static_cast<std::size_t>(x) * sizeof(double), sizeof(depth));
  return depth;
}

}  // namespace strok
