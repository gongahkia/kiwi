#pragma once

#include "color_image_view.hpp"
#include "depth_image_view.hpp"
#include "motion_vector_view.hpp"
#include "normal_image_view.hpp"

#include <optional>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
// A borrowed renderer input. Color is required. Optional depth and normals must have
// exactly the same pixel dimensions as color; the initial API does not resample them.
// Callers retain all pixel memory for the complete render call. RenderInput has no
// timestamp: each successful Renderer render is one fixed logical temporal step.
// lookahead_color is an optional adjacent future color image for temporal
// supersampling; it must match color dimensions and is consumed only when that
// RendererConfig option is enabled. Without it, temporal supersampling uses the
// prior Renderer input when available, otherwise color alone.
// motion_vectors is an optional source-resolution current-to-previous vector field.
// It is retained for future temporal history selection; current reconstruction
// continues to use internally inferred optical flow when appropriate.
// motion_vector_validity, when present, describes the matching motion_vectors view.
struct RenderInput {
  ColorImageView color;
  std::optional<DepthImageView> depth;
  std::optional<NormalImageView> normals;
  std::optional<ColorImageView> lookahead_color;
  std::optional<MotionVectorView> motion_vectors;
  std::optional<MotionVectorValidityView> motion_vector_validity;
};

}  // namespace strok
