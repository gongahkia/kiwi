#pragma once

#include <cstddef>

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

// A read-only borrowed motion-vector image. The caller keeps data valid and
// unchanged for the complete render call. Float32x2 stores dx, dy consecutively
// for each color pixel. At current source-image coordinate (x, y), the vector
// identifies the immediately preceding source-image coordinate (x + dx, y + dy).
// +x points right and +y points down. Values are source-color pixel units, never
// normalized coordinates; RenderInput requires this view to match color dimensions.
// No invalid or disoccluded sentinel is defined yet. An absent view leaves current
// reconstruction behavior unchanged and allows internally inferred optical flow.
struct MotionVectorView {
  const float* data = nullptr;
  int width = 0;
  int height = 0;
  std::size_t row_stride_bytes = 0;
  MotionVectorPixelFormat pixel_format = MotionVectorPixelFormat::Float32x2;
  MotionVectorDirection direction = MotionVectorDirection::CurrentToPrevious;
  MotionVectorUnit unit = MotionVectorUnit::SourcePixels;
};

}  // namespace strok
