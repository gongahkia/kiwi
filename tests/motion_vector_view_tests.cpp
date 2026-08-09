#include "motion_vector_view.hpp"

#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <stdexcept>

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

  const std::array<std::uint8_t, 8> validity = {
    static_cast<std::uint8_t>(strok::MotionVectorValidity::Valid), 99U,
    static_cast<std::uint8_t>(strok::MotionVectorValidity::Invalid), 101U,
    static_cast<std::uint8_t>(strok::MotionVectorValidity::Disoccluded), 103U,
    static_cast<std::uint8_t>(strok::MotionVectorValidity::Valid), 105U,
  };
  const strok::MotionVectorValidityView padded_validity{
    .data = validity.data(),
    .width = 1,
    .height = 4,
    .row_stride_bytes = 2,
  };
  expect(!strok::motionVectorValidityViewError(padded_validity).has_value(), "padded motion-vector validity layout");
  expect(strok::motionVectorValidityAt(padded_validity, 0, 1) == strok::MotionVectorValidity::Invalid &&
             strok::motionVectorValidityAt(padded_validity, 0, 2) == strok::MotionVectorValidity::Disoccluded,
         "padded motion-vector validity sampling");
  expect(strok::motionVectorValidityDefined(strok::MotionVectorValidity::Valid) &&
             !strok::motionVectorValidityDefined(static_cast<strok::MotionVectorValidity>(99)),
         "defined motion-vector validity values");

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

  const auto expectInvalidValidity = [&](const strok::MotionVectorValidityView& image, const char* label) {
    expect(strok::motionVectorValidityViewError(image).has_value(), label);
  };
  expectInvalidValidity(strok::MotionVectorValidityView{
                          .data = nullptr,
                          .width = 1,
                          .height = 1,
                          .row_stride_bytes = 1,
                        },
                        "null motion-vector validity data");
  expectInvalidValidity(strok::MotionVectorValidityView{
                          .data = validity.data(),
                          .width = 0,
                          .height = 1,
                          .row_stride_bytes = 1,
                        },
                        "invalid motion-vector validity dimensions");
  expectInvalidValidity(strok::MotionVectorValidityView{
                          .data = validity.data(),
                          .width = 2,
                          .height = 1,
                          .row_stride_bytes = 1,
                        },
                        "undersized motion-vector validity stride");
  expectInvalidValidity(strok::MotionVectorValidityView{
                          .data = validity.data(),
                          .width = 1,
                          .height = std::numeric_limits<int>::max(),
                          .row_stride_bytes = std::numeric_limits<std::size_t>::max(),
                        },
                        "overflowing motion-vector validity layout");

  std::array<float, 8U * 4U * 2U> remap_vectors{};
  for (int y = 0; y < 4; ++y) {
    for (int x = 0; x < 8; ++x) {
      const std::size_t index = (static_cast<std::size_t>(y) * 8U + static_cast<std::size_t>(x)) * 2U;
      remap_vectors[index] = -2.0F;
      remap_vectors[index + 1U] = -1.0F;
    }
  }
  const strok::MotionVectorView remap_view{
    .data = remap_vectors.data(),
    .width = 8,
    .height = 4,
    .row_stride_bytes = 8U * 2U * sizeof(float),
  };
  std::array<std::uint8_t, 8U * 4U> remap_validity{};
  remap_validity.fill(static_cast<std::uint8_t>(strok::MotionVectorValidity::Valid));
  remap_validity[3U * 8U + 5U] = static_cast<std::uint8_t>(strok::MotionVectorValidity::Disoccluded);
  remap_validity[3U * 8U + 7U] = static_cast<std::uint8_t>(strok::MotionVectorValidity::Invalid);
  const strok::MotionVectorValidityView remap_validity_view{
    .data = remap_validity.data(),
    .width = 8,
    .height = 4,
    .row_stride_bytes = 8,
  };
  const strok::CellMotionField remapped = strok::remapMotionVectorsToCellGrid(remap_view, &remap_validity_view, 4, 2);
  expect(remapped.cols == 4 && remapped.rows == 2 && remapped.vectors.size() == 8U, "motion vectors remap to cell grid");
  expect(remapped.at(0, 0).validity == strok::MotionVectorValidity::Invalid, "out-of-bounds vector invalidated before history use");
  const strok::CellMotionVector scaled = remapped.at(1, 0);
  expect(scaled.validity == strok::MotionVectorValidity::Valid && scaled.dx == 1.0 && scaled.dy == 0.5,
         "source current-to-previous vector converts to scaled cell previous-to-current displacement");
  expect(remapped.at(2, 1).validity == strok::MotionVectorValidity::Disoccluded,
         "disocclusion status survives cell remapping");
  expect(remapped.at(3, 1).validity == strok::MotionVectorValidity::Invalid,
         "invalid status survives cell remapping");

  remap_vectors[(1U * 8U + 3U) * 2U] = std::numeric_limits<float>::quiet_NaN();
  const strok::CellMotionField nonfinite_remapped = strok::remapMotionVectorsToCellGrid(remap_view, nullptr, 4, 2);
  expect(nonfinite_remapped.at(1, 0).validity == strok::MotionVectorValidity::Invalid,
         "non-finite motion vector invalidated before history use");

  const strok::MotionVectorValidityView mismatched_validity_view{
    .data = remap_validity.data(),
    .width = 7,
    .height = 4,
    .row_stride_bytes = 7,
  };
  bool mismatched_validity = false;
  try {
    (void)strok::remapMotionVectorsToCellGrid(remap_view, &mismatched_validity_view, 4, 2);
  } catch (const std::invalid_argument&) {
    mismatched_validity = true;
  }
  expect(mismatched_validity, "motion-vector remap rejects mismatched validity dimensions");
}
