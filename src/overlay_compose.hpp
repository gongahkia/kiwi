#pragma once

#include "frame.hpp"
#include "scene_source.hpp"

namespace strok {

struct DepthOverlayOptions {
  double alpha = 0.65;
  double depth_threshold = 1.0e9;
};

Frame composeDepthOverlay(const Frame& base, const SceneGBuffer& overlay, DepthOverlayOptions options = {});

}  // namespace strok
