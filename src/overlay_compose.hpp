#pragma once

#include "frame.hpp"
#include "scene_source.hpp"

namespace contourtty {

struct DepthOverlayOptions {
  double alpha = 0.65;
  double depth_threshold = 1.0e9;
};

Frame composeDepthOverlay(const Frame& base, const SceneGBuffer& overlay, DepthOverlayOptions options = {});

}  // namespace contourtty
