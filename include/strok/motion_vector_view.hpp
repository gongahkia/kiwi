#pragma once

#include <cstddef>
#include <cstdint>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
enum class MotionVectorPixelFormat {
  Float32x2,
};

enum class MotionVectorDirection {
  CurrentToPrevious,
};

enum class MotionVectorUnit {
  SourcePixels,
};

enum class MotionVectorValidity : std::uint8_t {
  Valid = 0,
  Invalid = 1,
  Disoccluded = 2,
};

// A read-only borrowed motion-vector image. The caller keeps data valid and
// unchanged for the complete render call. Float32x2 stores dx, dy consecutively
// for each color pixel. At current source-image coordinate (x, y), the vector
// identifies the immediately preceding source-image coordinate (x + dx, y + dy).
// +x points right and +y points down. Values are source-color pixel units, never
// normalized coordinates; RenderInput requires this view to match color dimensions.
// Cell-grid remapping samples the source pixel nearest each cell center, inverts this
// current-to-previous direction, and scales dx by grid_cols / width and dy by
// grid_rows / height. Vectors whose previous source coordinate is out of bounds are
// remapped as Invalid before temporal history can use them.
// Validity and disocclusion state is carried by MotionVectorValidityView rather than
// a vector sentinel. An absent view leaves current reconstruction behavior unchanged
// and allows internally inferred optical flow.
struct MotionVectorView {
  const float* data = nullptr;
  int width = 0;
  int height = 0;
  std::size_t row_stride_bytes = 0;
  MotionVectorPixelFormat pixel_format = MotionVectorPixelFormat::Float32x2;
  MotionVectorDirection direction = MotionVectorDirection::CurrentToPrevious;
  MotionVectorUnit unit = MotionVectorUnit::SourcePixels;
};

// A read-only borrowed per-pixel status for a MotionVectorView. Values are one
// byte per source-color pixel: Valid selects the supplied vector, Invalid permits
// future fallback to internally inferred optical flow, and Disoccluded forbids
// future history reuse. Any other value is invalid input. An absent view means all
// supplied vectors are Valid. The caller keeps data valid and unchanged for the
// complete render call; RenderInput requires this view to match color dimensions.
// Cell-grid remapping preserves sampled Invalid and Disoccluded statuses.
struct MotionVectorValidityView {
  const std::uint8_t* data = nullptr;
  int width = 0;
  int height = 0;
  std::size_t row_stride_bytes = 0;
};

}  // namespace strok
