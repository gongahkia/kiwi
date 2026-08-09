#include "motion_vector_view.hpp"

#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  const std::array<float, 12> vectors = {
    1.0F, -2.0F, 99.0F,
    3.0F, -4.0F, 101.0F,
    5.0F, -6.0F, 103.0F,
    7.0F, -8.0F, 105.0F,
  };
  const strok::MotionVectorView padded{
    .data = vectors.data(),
    .width = 1,
    .height = 4,
    .row_stride_bytes = 3U * sizeof(float),
    .pixel_format = strok::MotionVectorPixelFormat::Float32x2,
    .direction = strok::MotionVectorDirection::CurrentToPrevious,
    .unit = strok::MotionVectorUnit::SourcePixels,
  };
  expect(!strok::motionVectorViewError(padded).has_value(), "padded Float32x2 motion-vector layout");
  const strok::MotionVectorSample fourth = strok::motionVectorAt(padded, 0, 3);
  expect(fourth.x == 7.0F && fourth.y == -8.0F, "padded Float32x2 motion-vector sampling");

  const auto expectInvalid = [&](const strok::MotionVectorView& image, const char* label) {
    expect(strok::motionVectorViewError(image).has_value(), label);
  };
  expectInvalid(strok::MotionVectorView{
                  .data = nullptr,
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = 2U * sizeof(float),
                },
                "null motion-vector data");
  expectInvalid(strok::MotionVectorView{
                  .data = vectors.data(),
                  .width = 0,
                  .height = 1,
                  .row_stride_bytes = 2U * sizeof(float),
                },
                "invalid motion-vector dimensions");
  expectInvalid(strok::MotionVectorView{
                  .data = vectors.data(),
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = sizeof(float),
                },
                "undersized motion-vector stride");
  expectInvalid(strok::MotionVectorView{
                  .data = vectors.data(),
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = 2U * sizeof(float) + 1U,
                },
                "unaligned motion-vector stride");
  expectInvalid(strok::MotionVectorView{
                  .data = vectors.data(),
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = 2U * sizeof(float),
                  .pixel_format = static_cast<strok::MotionVectorPixelFormat>(99),
                },
                "unsupported motion-vector format");
  expectInvalid(strok::MotionVectorView{
                  .data = vectors.data(),
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = 2U * sizeof(float),
                  .direction = static_cast<strok::MotionVectorDirection>(99),
                },
                "unsupported motion-vector direction");
  expectInvalid(strok::MotionVectorView{
                  .data = vectors.data(),
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = 2U * sizeof(float),
                  .unit = static_cast<strok::MotionVectorUnit>(99),
                },
                "unsupported motion-vector unit");
  expectInvalid(strok::MotionVectorView{
                  .data = vectors.data(),
                  .width = 1,
                  .height = std::numeric_limits<int>::max(),
                  .row_stride_bytes = std::numeric_limits<std::size_t>::max() / sizeof(float) * sizeof(float),
                },
                "overflowing motion-vector layout");
}
