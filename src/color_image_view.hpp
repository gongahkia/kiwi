#pragma once

#include "../include/strok/color_image_view.hpp"
#include "../include/strok/color.hpp"

#include "frame.hpp"

#include <cstddef>
#include <limits>
#include <optional>
#include <string>

namespace strok {

inline std::optional<std::string> colorImageViewError(const ColorImageView& image) {
  if (image.data == nullptr) {
    return "color image data is required";
  }
  if (image.width <= 0 || image.height <= 0) {
    return "color image dimensions must be positive";
  }
  if (image.pixel_format != ColorPixelFormat::Rgb24) {
    return "color image pixel format is unsupported";
  }

  const std::size_t width = static_cast<std::size_t>(image.width);
  const std::size_t height = static_cast<std::size_t>(image.height);
  if (width > std::numeric_limits<std::size_t>::max() / height) {
    return "color image dimensions overflow";
  }
  if (width > std::numeric_limits<std::size_t>::max() / 3U) {
    return "color image row size overflows";
  }
  const std::size_t row_bytes = width * 3U;
  if (image.row_stride_bytes < row_bytes) {
    return "color image row stride is smaller than RGB24 row size";
  }

  const std::size_t rows_before_last = height - 1U;
  if (rows_before_last > 0 && image.row_stride_bytes > (std::numeric_limits<std::size_t>::max() - row_bytes) / rows_before_last) {
    return "color image layout overflows";
  }
  return std::nullopt;
}

inline ColorImageView colorImageViewFromFrame(const Frame& frame) noexcept {
  const std::size_t width = frame.w > 0 ? static_cast<std::size_t>(frame.w) : 0U;
  const std::size_t row_stride = width <= std::numeric_limits<std::size_t>::max() / 3U ? width * 3U : 0U;
  return ColorImageView{
    .data = frame.rgb.data(),
    .width = frame.w,
    .height = frame.h,
    .row_stride_bytes = row_stride,
    .pixel_format = ColorPixelFormat::Rgb24,
  };
}

inline Rgb colorAt(const ColorImageView& image, int x, int y) noexcept {
  const std::size_t row = static_cast<std::size_t>(y) * image.row_stride_bytes;
  const std::size_t pixel = row + static_cast<std::size_t>(x) * 3U;
  return Rgb{
    .r = image.data[pixel],
    .g = image.data[pixel + 1U],
    .b = image.data[pixel + 2U],
  };
}

}  // namespace strok
