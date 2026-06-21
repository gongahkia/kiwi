#include "overlay_compose.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <stdexcept>

namespace contourtty {
namespace {

uint8_t blendChannel(uint8_t bg, uint8_t fg, double alpha) noexcept {
  return static_cast<uint8_t>(std::clamp(std::lround(static_cast<double>(bg) * (1.0 - alpha) + static_cast<double>(fg) * alpha), 0L, 255L));
}

}  // namespace

Frame composeDepthOverlay(const Frame& base, const SceneGBuffer& overlay, DepthOverlayOptions options) {
  if (base.w <= 0 || base.h <= 0 || overlay.albedo.w != base.w || overlay.albedo.h != base.h) {
    throw std::invalid_argument("overlay dimensions must match base frame");
  }
  const std::size_t pixels = static_cast<std::size_t>(base.w) * static_cast<std::size_t>(base.h);
  if (base.rgb.size() != pixels * 3U || overlay.albedo.rgb.size() != pixels * 3U || overlay.depth.size() != pixels) {
    throw std::invalid_argument("overlay buffers must match dimensions");
  }
  const double alpha = std::clamp(options.alpha, 0.0, 1.0);
  Frame output = base;
  for (std::size_t index = 0; index < pixels; ++index) {
    const double depth = overlay.depth[index];
    if (!std::isfinite(depth) || depth > options.depth_threshold) {
      continue;
    }
    const std::size_t rgb = index * 3U;
    output.rgb[rgb] = blendChannel(base.rgb[rgb], overlay.albedo.rgb[rgb], alpha);
    output.rgb[rgb + 1U] = blendChannel(base.rgb[rgb + 1U], overlay.albedo.rgb[rgb + 1U], alpha);
    output.rgb[rgb + 2U] = blendChannel(base.rgb[rgb + 2U], overlay.albedo.rgb[rgb + 2U], alpha);
  }
  return output;
}

}  // namespace contourtty
