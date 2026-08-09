#pragma once

#include "color_image_view.hpp"

#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <vector>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
struct Frame {
  int w = 0;
  int h = 0;
  std::vector<uint8_t> rgb;
  // Source presentation timestamp metadata in microseconds. The core Renderer does
  // not read it; frontends own pacing and pass ordered frames to render calls.
  int64_t pts_us = 0;
};

inline std::optional<ColorImageView> colorImageViewFromFrame(const Frame& frame) noexcept {
  if (frame.w <= 0 || frame.h <= 0) {
    return std::nullopt;
  }
  const std::size_t width = static_cast<std::size_t>(frame.w);
  const std::size_t height = static_cast<std::size_t>(frame.h);
  if (width > std::numeric_limits<std::size_t>::max() / height) {
    return std::nullopt;
  }
  const std::size_t pixels = width * height;
  if (pixels > std::numeric_limits<std::size_t>::max() / 3U || frame.rgb.size() != pixels * 3U) {
    return std::nullopt;
  }
  return ColorImageView{
    .data = frame.rgb.data(),
    .width = frame.w,
    .height = frame.h,
    .row_stride_bytes = width * 3U,
    .pixel_format = ColorPixelFormat::Rgb24,
  };
}

}  // namespace strok
