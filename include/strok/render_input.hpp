#pragma once

#include "color_image_view.hpp"
#include "depth_image_view.hpp"
#include "normal_image_view.hpp"

#include <optional>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
// A borrowed renderer input. Color is required. Optional depth and normals must have
// exactly the same pixel dimensions as color; the initial API does not resample them.
// Callers retain all pixel memory for the complete render call.
struct RenderInput {
  ColorImageView color;
  std::optional<DepthImageView> depth;
  std::optional<NormalImageView> normals;
};

}  // namespace strok
