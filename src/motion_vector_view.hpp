#pragma once

#include "../include/strok/motion_vector_view.hpp"

#include <cstddef>
#include <cstring>
#include <limits>
#include <optional>
#include <string>

namespace strok {

struct MotionVectorSample {
  float x = 0.0F;
  float y = 0.0F;
};

inline std::optional<std::string> motionVectorViewError(const MotionVectorView& image) {
  if (image.data == nullptr) {
    return "motion vector data is required";
  }
  if (image.width <= 0 || image.height <= 0) {
    return "motion vector dimensions must be positive";
  }
  if (image.pixel_format != MotionVectorPixelFormat::Float32x2) {
    return "motion vector pixel format is unsupported";
  }
  if (image.direction != MotionVectorDirection::CurrentToPrevious) {
    return "motion vector direction is unsupported";
  }
  if (image.unit != MotionVectorUnit::SourcePixels) {
    return "motion vector unit is unsupported";
  }
  if (image.row_stride_bytes % sizeof(float) != 0U) {
    return "motion vector row stride must preserve Float32 alignment";
  }

  const std::size_t width = static_cast<std::size_t>(image.width);
  const std::size_t height = static_cast<std::size_t>(image.height);
  if (width > std::numeric_limits<std::size_t>::max() / height) {
    return "motion vector dimensions overflow";
  }
  constexpr std::size_t components_per_pixel = 2U;
  if (width > std::numeric_limits<std::size_t>::max() / (components_per_pixel * sizeof(float))) {
    return "motion vector row size overflows";
  }
  const std::size_t row_bytes = width * components_per_pixel * sizeof(float);
  if (image.row_stride_bytes < row_bytes) {
    return "motion vector row stride is smaller than Float32x2 row size";
  }

  const std::size_t rows_before_last = height - 1U;
  if (rows_before_last > 0 && image.row_stride_bytes > (std::numeric_limits<std::size_t>::max() - row_bytes) / rows_before_last) {
    return "motion vector layout overflows";
  }
  return std::nullopt;
}

inline MotionVectorSample motionVectorAt(const MotionVectorView& image, int x, int y) noexcept {
  const auto* row = reinterpret_cast<const unsigned char*>(image.data) + static_cast<std::size_t>(y) * image.row_stride_bytes;
  MotionVectorSample vector;
  const auto* pixel = row + static_cast<std::size_t>(x) * 2U * sizeof(float);
  std::memcpy(&vector.x, pixel, sizeof(vector.x));
  std::memcpy(&vector.y, pixel + sizeof(float), sizeof(vector.y));
  return vector;
}

inline bool motionVectorValidityDefined(MotionVectorValidity validity) noexcept {
  return validity == MotionVectorValidity::Valid ||
         validity == MotionVectorValidity::Invalid ||
         validity == MotionVectorValidity::Disoccluded;
}

inline std::optional<std::string> motionVectorValidityViewError(const MotionVectorValidityView& image) {
  if (image.data == nullptr) {
    return "motion vector validity data is required";
  }
  if (image.width <= 0 || image.height <= 0) {
    return "motion vector validity dimensions must be positive";
  }

  const std::size_t width = static_cast<std::size_t>(image.width);
  const std::size_t height = static_cast<std::size_t>(image.height);
  if (width > std::numeric_limits<std::size_t>::max() / height) {
    return "motion vector validity dimensions overflow";
  }
  if (image.row_stride_bytes < width) {
    return "motion vector validity row stride is smaller than byte row size";
  }

  const std::size_t rows_before_last = height - 1U;
  if (rows_before_last > 0 && image.row_stride_bytes > (std::numeric_limits<std::size_t>::max() - width) / rows_before_last) {
    return "motion vector validity layout overflows";
  }
  return std::nullopt;
}

inline MotionVectorValidity motionVectorValidityAt(const MotionVectorValidityView& image, int x, int y) noexcept {
  const auto* row = image.data + static_cast<std::size_t>(y) * image.row_stride_bytes;
  return static_cast<MotionVectorValidity>(row[x]);
}

}  // namespace strok
