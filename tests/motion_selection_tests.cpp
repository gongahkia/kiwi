#include <strok/renderer.hpp>

#include "renderer.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>

namespace {

constexpr int kWidth = 16;
constexpr int kHeight = 16;
constexpr int kCols = 2;
constexpr int kRows = 2;

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::Frame textureFrame(int offset) {
  strok::Frame frame{
    .w = kWidth,
    .h = kHeight,
    .rgb = {},
  };
  frame.rgb.reserve(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight) * 3U);
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      const int source_x = x - offset;
      const std::uint8_t value = source_x < 0
                                   ? 0U
                                   : static_cast<std::uint8_t>((source_x * 17 + y * 29 + source_x * y * 5) % 251);
      frame.rgb.insert(frame.rgb.end(), {value, value, value});
    }
  }
  return frame;
}

strok::Frame angledEdgeFrame(int numerator, int denominator) {
  strok::Frame frame{
    .w = kWidth,
    .h = kHeight,
    .rgb = {},
  };
  frame.rgb.reserve(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight) * 3U);
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      const int distance = x * denominator + y * numerator - ((kWidth / 2) * denominator);
      const std::uint8_t value = distance < 0 ? 0U : 255U;
      frame.rgb.insert(frame.rgb.end(), {value, value, value});
    }
  }
  return frame;
}

strok::ColorImageView viewFor(const strok::Frame& frame) {
  return strok::ColorImageView{
    .data = frame.rgb.data(),
    .width = frame.w,
    .height = frame.h,
    .row_stride_bytes = static_cast<std::size_t>(frame.w) * 3U,
    .pixel_format = strok::ColorPixelFormat::Rgb24,
  };
}

strok::Renderer::CreateResult createRenderer(double glyph_stickiness = 0.05, bool temporal_cell_reuse = false) {
  strok::RendererConfig config;
  config.cell_aspect = 1.0;
  config.mode = "structure";
  config.edge_threshold = 0.01;
  config.glyph_stickiness = glyph_stickiness;
  config.temporal_cell_reuse = temporal_cell_reuse;
  return strok::Renderer::create(config, strok::RenderGrid{.cols = kCols, .rows = kRows});
}

strok::RenderResult renderFollowup(const strok::RenderInput& input) {
  strok::Renderer::CreateResult created = createRenderer();
  expect(created.succeeded(), "motion selection renderer construction");
  expect(created.renderer->render(textureFrame(0)).succeeded(), "motion selection initial frame");
  return created.renderer->render(input);
}

std::vector<float> zeroMotionVectors() {
  return std::vector<float>(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight) * 2U, 0.0F);
}

strok::MotionVectorView motionViewFor(const std::vector<float>& vectors) {
  return strok::MotionVectorView{
    .data = vectors.data(),
    .width = kWidth,
    .height = kHeight,
    .row_stride_bytes = static_cast<std::size_t>(kWidth) * 2U * sizeof(float),
  };
}

}  // namespace

int main() {
  const strok::Frame current = textureFrame(1);
  const strok::ColorImageView current_view = viewFor(current);

  const strok::RenderResult inferred = renderFollowup(strok::RenderInput{.color = current_view});
  expect(inferred.succeeded() && inferred.stats.optical_flow_blocks > 0,
         "RGB-only follow-up uses inferred optical flow");
  expect(inferred.stats.external_motion_cells == 0 && inferred.stats.inferred_motion_cells == kCols * kRows,
         "RGB-only follow-up reports inferred history cells");
  expect(inferred.stats.warp_history_cells > 0, "RGB-only follow-up warps temporal history");

  const std::vector<float> all_valid_vectors = zeroMotionVectors();
  const strok::RenderResult external = renderFollowup(strok::RenderInput{
      .color = current_view,
      .motion_vectors = motionViewFor(all_valid_vectors),
    });
  expect(external.succeeded() && external.stats.optical_flow_blocks == 0,
         "valid external vectors bypass inferred optical flow");
  expect(external.stats.external_motion_cells == kCols * kRows && external.stats.inferred_motion_cells == 0,
         "valid external vectors select every history cell");
  expect(external.stats.warp_history_cells > 0, "valid external vectors warp temporal history");

  const std::vector<float> mixed_vectors = zeroMotionVectors();
  std::vector<std::uint8_t> mixed_validity(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight),
                                           static_cast<std::uint8_t>(strok::MotionVectorValidity::Valid));
  mixed_validity[static_cast<std::size_t>(kHeight / 4) * static_cast<std::size_t>(kWidth) + static_cast<std::size_t>(kWidth / 4)] =
      static_cast<std::uint8_t>(strok::MotionVectorValidity::Invalid);
  const strok::RenderResult mixed = renderFollowup(strok::RenderInput{
      .color = current_view,
      .motion_vectors = motionViewFor(mixed_vectors),
      .motion_vector_validity = strok::MotionVectorValidityView{
        .data = mixed_validity.data(),
        .width = kWidth,
        .height = kHeight,
        .row_stride_bytes = static_cast<std::size_t>(kWidth),
      },
    });
  expect(mixed.succeeded() && mixed.stats.optical_flow_blocks > 0,
         "invalid external cell computes inferred fallback");
  expect(mixed.stats.external_motion_cells == kCols * kRows - 1 && mixed.stats.inferred_motion_cells == 1,
         "mixed validity selects external and inferred history per cell");
  expect(mixed.stats.warp_history_cells > 0, "mixed validity still warps temporal history");

  std::vector<std::uint8_t> disoccluded_validity(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight),
                                                  static_cast<std::uint8_t>(strok::MotionVectorValidity::Valid));
  disoccluded_validity[static_cast<std::size_t>(kHeight / 4) * static_cast<std::size_t>(kWidth) + static_cast<std::size_t>(kWidth / 4)] =
      static_cast<std::uint8_t>(strok::MotionVectorValidity::Disoccluded);
  disoccluded_validity[static_cast<std::size_t>(kHeight / 4) * static_cast<std::size_t>(kWidth) + static_cast<std::size_t>(kWidth * 3 / 4)] =
      static_cast<std::uint8_t>(strok::MotionVectorValidity::Invalid);
  strok::Renderer::CreateResult disoccluded_renderer = createRenderer(1.0, true);
  expect(disoccluded_renderer.succeeded(), "disocclusion renderer construction");
  expect(disoccluded_renderer.renderer->render(textureFrame(0)).succeeded(), "disocclusion initial frame");
  const strok::RenderResult disoccluded = disoccluded_renderer.renderer->render(strok::RenderInput{
      .color = current_view,
      .motion_vectors = motionViewFor(mixed_vectors),
      .motion_vector_validity = strok::MotionVectorValidityView{
        .data = disoccluded_validity.data(),
        .width = kWidth,
        .height = kHeight,
        .row_stride_bytes = static_cast<std::size_t>(kWidth),
      },
    });
  expect(disoccluded.succeeded() && disoccluded.stats.history_suppressed_cells == 1,
         "disoccluded cell reports history suppression");
  expect(disoccluded.stats.optical_flow_blocks > 0 &&
             disoccluded.stats.external_motion_cells == kCols * kRows - 2 && disoccluded.stats.inferred_motion_cells == 1,
         "disocclusion suppresses only its cell while invalid motion uses fallback");
  strok::Renderer::CreateResult current_only_renderer = createRenderer(1.0);
  expect(current_only_renderer.succeeded() && current_only_renderer.renderer->render(current).succeeded(),
         "current-only comparison renderer");
  expect(disoccluded_renderer.renderer->cells().at(0, 0) == current_only_renderer.renderer->cells().at(0, 0),
         "disoccluded cell reconstructs from current frame instead of stale history");

  strok::RendererConfig orientation_config;
  orientation_config.cell_aspect = 1.0;
  orientation_config.mode = "structure";
  orientation_config.edge_threshold = 0.01;
  orientation_config.glyph_stickiness = 0.0;
  orientation_config.orient_stickiness = 0.60;
  strok::RenderTemporalState orientation_state;
  strok::CellBuffer orientation_cells;
  expect(strok::renderFrame(angledEdgeFrame(0, 1), U" @", orientation_config, strok::RenderGrid{.cols = 1, .rows = 1}, nullptr, &orientation_cells, &orientation_state).succeeded() &&
             orientation_cells.at(0, 0).glyph == U'|',
         "orientation suppression fixture starts vertical");
  const std::vector<float> orientation_vectors = zeroMotionVectors();
  std::vector<std::uint8_t> orientation_disoccluded(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight),
                                                     static_cast<std::uint8_t>(strok::MotionVectorValidity::Disoccluded));
  const strok::Frame orientation_current = angledEdgeFrame(1, 2);
  expect(strok::renderFrame(strok::RenderInput{
      .color = viewFor(orientation_current),
      .motion_vectors = motionViewFor(orientation_vectors),
      .motion_vector_validity = strok::MotionVectorValidityView{
        .data = orientation_disoccluded.data(),
        .width = kWidth,
        .height = kHeight,
        .row_stride_bytes = static_cast<std::size_t>(kWidth),
      },
    }, U" @", orientation_config, strok::RenderGrid{.cols = 1, .rows = 1}, nullptr, &orientation_cells, &orientation_state).succeeded(),
         "orientation disocclusion frame");
  expect(orientation_cells.at(0, 0).glyph == U'/', "disocclusion clears orientation hysteresis");
}
