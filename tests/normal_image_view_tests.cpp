#include "normal_image_view.hpp"

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
  const std::array<double, 8> normals = {0.0, 0.0, 2.0, 99.0, 1.0, 0.0, 0.0, 101.0};
  const strok::NormalImageView padded{
    .data = normals.data(),
    .width = 1,
    .height = 2,
    .row_stride_bytes = 4U * sizeof(double),
    .pixel_format = strok::NormalPixelFormat::Float64x3,
    .space = strok::NormalSpace::View,
  };
  expect(!strok::normalImageViewError(padded).has_value(), "padded Float64x3 normal layout");
  const strok::NormalSample second = strok::normalAt(padded, 0, 1);
  expect(second.x == 1.0 && second.y == 0.0 && second.z == 0.0, "padded Float64x3 normal sampling");
  const strok::NormalSample normalized = strok::normalizedNormalSampleOrViewFacing(strok::NormalSample{.z = 2.0});
  expect(normalized.x == 0.0 && normalized.y == 0.0 && normalized.z == 1.0, "normal sample normalization");
  const strok::NormalSample zero_normal{.x = 0.0, .y = 0.0, .z = 0.0};
  expect(!strok::normalSampleValid(zero_normal) && !strok::normalSampleValid(strok::NormalSample{.x = std::numeric_limits<double>::quiet_NaN()}), "invalid normal samples");
  const strok::NormalSample fallback = strok::normalizedNormalSampleOrViewFacing(zero_normal);
  expect(fallback.x == 0.0 && fallback.y == 0.0 && fallback.z == 1.0, "invalid normal fallback");

  const auto expectInvalid = [&](const strok::NormalImageView& image, const char* label) {
    expect(strok::normalImageViewError(image).has_value(), label);
  };
  expectInvalid(strok::NormalImageView{
                  .data = nullptr,
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = 3U * sizeof(double),
                },
                "null normal data");
  expectInvalid(strok::NormalImageView{
                  .data = normals.data(),
                  .width = 0,
                  .height = 1,
                  .row_stride_bytes = 3U * sizeof(double),
                },
                "invalid normal dimensions");
  expectInvalid(strok::NormalImageView{
                  .data = normals.data(),
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = 2U * sizeof(double),
                },
                "undersized normal stride");
  expectInvalid(strok::NormalImageView{
                  .data = normals.data(),
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = 3U * sizeof(double) + 1U,
                },
                "unaligned normal stride");
  expectInvalid(strok::NormalImageView{
                  .data = normals.data(),
                  .width = 1,
                  .height = std::numeric_limits<int>::max(),
                  .row_stride_bytes = std::numeric_limits<std::size_t>::max() / sizeof(double) * sizeof(double),
                },
                "overflowing normal layout");
}
