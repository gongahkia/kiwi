#include "depth_image_view.hpp"

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
  const std::array<double, 6> depth = {1.0, 2.0, 99.0, 3.0, 4.0, 101.0};
  const strok::DepthImageView padded{
    .data = depth.data(),
    .width = 2,
    .height = 2,
    .row_stride_bytes = 3U * sizeof(double),
    .pixel_format = strok::DepthPixelFormat::Float64,
    .interpretation = strok::DepthInterpretation::CameraLinear,
  };
  expect(!strok::depthImageViewError(padded).has_value(), "padded Float64 depth layout");
  expect(strok::depthAt(padded, 1, 1) == 4.0, "padded Float64 depth sampling");
  expect(strok::depthSampleValid(1.0) && !strok::depthSampleValid(std::numeric_limits<double>::infinity()) && !strok::depthSampleValid(std::numeric_limits<double>::quiet_NaN()), "depth sample validity");

  const auto expectInvalid = [&](const strok::DepthImageView& image, const char* label) {
    expect(strok::depthImageViewError(image).has_value(), label);
  };
  expectInvalid(strok::DepthImageView{
                  .data = nullptr,
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = sizeof(double),
                },
                "null depth data");
  expectInvalid(strok::DepthImageView{
                  .data = depth.data(),
                  .width = 0,
                  .height = 1,
                  .row_stride_bytes = sizeof(double),
                },
                "invalid depth dimensions");
  expectInvalid(strok::DepthImageView{
                  .data = depth.data(),
                  .width = 2,
                  .height = 1,
                  .row_stride_bytes = sizeof(double),
                },
                "undersized depth stride");
  expectInvalid(strok::DepthImageView{
                  .data = depth.data(),
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = sizeof(double) + 1U,
                },
                "unaligned depth stride");
  expectInvalid(strok::DepthImageView{
                  .data = depth.data(),
                  .width = 1,
                  .height = std::numeric_limits<int>::max(),
                  .row_stride_bytes = std::numeric_limits<std::size_t>::max() / sizeof(double) * sizeof(double),
                },
                "overflowing depth layout");
}
