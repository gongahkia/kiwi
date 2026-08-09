#pragma once

#include "../include/strok/normal_image_view.hpp"

#include <cmath>
#include <cstddef>
#include <cstring>
#include <limits>
#include <optional>
#include <string>

namespace strok {

struct NormalSample {
  double x = 0.0;
  double y = 0.0;
  double z = 1.0;
};

inline bool normalSampleValid(NormalSample normal) noexcept {
  const double length_squared = normal.x * normal.x + normal.y * normal.y + normal.z * normal.z;
  return std::isfinite(normal.x) && std::isfinite(normal.y) && std::isfinite(normal.z) && std::isfinite(length_squared) && length_squared > 1.0e-24;
}

inline NormalSample normalizedNormalSampleOrViewFacing(NormalSample normal) noexcept {
  if (!normalSampleValid(normal)) {
    return NormalSample{};
  }
  const double inverse_length = 1.0 / std::sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
  return NormalSample{
    .x = normal.x * inverse_length,
    .y = normal.y * inverse_length,
    .z = normal.z * inverse_length,
  };
}

inline std::optional<std::string> normalImageViewError(const NormalImageView& image) {
  if (image.data == nullptr) {
    return "normal image data is required";
  }
  if (image.width <= 0 || image.height <= 0) {
    return "normal image dimensions must be positive";
  }
  if (image.pixel_format != NormalPixelFormat::Float64x3) {
    return "normal image pixel format is unsupported";
  }
  if (image.space != NormalSpace::View) {
    return "normal image space is unsupported";
  }
  if (image.row_stride_bytes % sizeof(double) != 0U) {
    return "normal image row stride must preserve Float64 alignment";
  }

  const std::size_t width = static_cast<std::size_t>(image.width);
  const std::size_t height = static_cast<std::size_t>(image.height);
  if (width > std::numeric_limits<std::size_t>::max() / height) {
    return "normal image dimensions overflow";
  }
  constexpr std::size_t components_per_pixel = 3U;
  if (width > std::numeric_limits<std::size_t>::max() / (components_per_pixel * sizeof(double))) {
    return "normal image row size overflows";
  }
  const std::size_t row_bytes = width * components_per_pixel * sizeof(double);
  if (image.row_stride_bytes < row_bytes) {
    return "normal image row stride is smaller than Float64x3 row size";
  }

  const std::size_t rows_before_last = height - 1U;
  if (rows_before_last > 0 && image.row_stride_bytes > (std::numeric_limits<std::size_t>::max() - row_bytes) / rows_before_last) {
    return "normal image layout overflows";
  }
  return std::nullopt;
}

inline NormalSample normalAt(const NormalImageView& image, int x, int y) noexcept {
  const auto* row = reinterpret_cast<const unsigned char*>(image.data) + static_cast<std::size_t>(y) * image.row_stride_bytes;
  NormalSample normal;
  const auto* pixel = row + static_cast<std::size_t>(x) * 3U * sizeof(double);
  std::memcpy(&normal.x, pixel, sizeof(normal.x));
  std::memcpy(&normal.y, pixel + sizeof(double), sizeof(normal.y));
  std::memcpy(&normal.z, pixel + 2U * sizeof(double), sizeof(normal.z));
  return normal;
}

}  // namespace strok
