#include <strok/renderer.hpp>

#include "temporal_stability_metric.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>

namespace {

constexpr int kWidth = 32;
constexpr int kHeight = 16;

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

enum class MotionMode {
  Inferred,
  External,
  Invalid,
  Disoccluded,
};

strok::Frame translatedTextureFrame(int offset, bool occlude_top_left) {
  strok::Frame frame{
    .w = kWidth,
    .h = kHeight,
    .rgb = {},
  };
  frame.rgb.reserve(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight) * 3U);
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      const int source_x = x - offset;
      std::uint8_t value = source_x < 0
                             ? 0U
                             : static_cast<std::uint8_t>((source_x * 13 + y * 31 + source_x * y * 7) % 251);
      if (occlude_top_left && x < kWidth / 4 && y < kHeight / 2) {
        value = 255U;
      }
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

std::vector<float> translationVectors() {
  std::vector<float> vectors(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight) * 2U, 0.0F);
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 1; x < kWidth; ++x) {
      vectors[(static_cast<std::size_t>(y) * static_cast<std::size_t>(kWidth) + static_cast<std::size_t>(x)) * 2U] = -1.0F;
    }
  }
  return vectors;
}

void setCellValidity(std::vector<std::uint8_t>* validity, strok::RenderGrid grid, int col, int row, strok::MotionVectorValidity value) {
  const int source_x = static_cast<int>((static_cast<double>(col) + 0.5) * kWidth / grid.cols);
  const int source_y = static_cast<int>((static_cast<double>(row) + 0.5) * kHeight / grid.rows);
  validity->at(static_cast<std::size_t>(source_y) * static_cast<std::size_t>(kWidth) + static_cast<std::size_t>(source_x)) =
      static_cast<std::uint8_t>(value);
}

struct Sequence {
  std::vector<strok::CellBuffer> cells;
  std::vector<strok::RenderStats> stats;
  strok_test::TemporalStability metric;
};

Sequence renderSequence(strok::RenderGrid grid, MotionMode mode) {
  strok::RendererConfig config;
  config.cell_aspect = 1.0;
  config.mode = "structure";
  config.edge_threshold = 0.01;
  config.glyph_stickiness = 0.05;
  strok::Renderer::CreateResult created = strok::Renderer::create(config, grid);
  expect(created.succeeded(), "motion comparison renderer construction");

  const std::vector<strok::Frame> frames{
    translatedTextureFrame(0, false),
    translatedTextureFrame(1, mode == MotionMode::Disoccluded),
    translatedTextureFrame(2, false),
  };
  const std::vector<float> vectors = translationVectors();
  const strok::MotionVectorView motion_view{
    .data = vectors.data(),
    .width = kWidth,
    .height = kHeight,
    .row_stride_bytes = static_cast<std::size_t>(kWidth) * 2U * sizeof(float),
  };

  Sequence sequence;
  for (std::size_t index = 0; index < frames.size(); ++index) {
    strok::RenderResult result;
    if (index == 0 || mode == MotionMode::Inferred) {
      result = created.renderer->render(frames[index]);
    } else {
      std::vector<std::uint8_t> validity(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight),
                                         static_cast<std::uint8_t>(strok::MotionVectorValidity::Valid));
      if (mode == MotionMode::Invalid) {
        setCellValidity(&validity, grid, 0, 0, strok::MotionVectorValidity::Invalid);
      } else if (mode == MotionMode::Disoccluded) {
        setCellValidity(&validity, grid, 0, 0, strok::MotionVectorValidity::Disoccluded);
      }
      result = created.renderer->render(strok::RenderInput{
          .color = viewFor(frames[index]),
          .motion_vectors = motion_view,
          .motion_vector_validity = strok::MotionVectorValidityView{
            .data = validity.data(),
            .width = kWidth,
            .height = kHeight,
            .row_stride_bytes = static_cast<std::size_t>(kWidth),
          },
        });
    }
    expect(result.succeeded(), "motion comparison frame render");
    sequence.cells.push_back(created.renderer->cells());
    sequence.stats.push_back(result.stats);
  }
  sequence.metric = strok_test::measureSequence(sequence.cells);
  return sequence;
}

}  // namespace

int main() {
  const strok::RenderGrid grid{.cols = 4, .rows = 2};
  const Sequence inferred = renderSequence(grid, MotionMode::Inferred);
  const Sequence external_first = renderSequence(grid, MotionMode::External);
  const Sequence external_second = renderSequence(grid, MotionMode::External);
  expect(external_first.cells == external_second.cells && external_first.metric == external_second.metric,
         "external translation fixture is repeatable");
  expect(inferred.metric.compared_cells == external_first.metric.compared_cells &&
             inferred.metric.changed_cells <= inferred.metric.compared_cells &&
             external_first.metric.changed_cells <= external_first.metric.compared_cells,
         "external and inferred runs report comparable CellBuffer churn");
  expect(inferred.stats[1].optical_flow_blocks > 0 && inferred.stats[1].inferred_motion_cells == grid.cols * grid.rows,
         "RGB-only inferred flow remains the baseline");
  expect(external_first.stats[1].optical_flow_blocks == 0 && external_first.stats[1].external_motion_cells == grid.cols * grid.rows,
         "external translation selects remapped history without inference");

  const Sequence invalid = renderSequence(grid, MotionMode::Invalid);
  expect(invalid.stats[1].optical_flow_blocks > 0 &&
             invalid.stats[1].external_motion_cells == grid.cols * grid.rows - 1 && invalid.stats[1].inferred_motion_cells == 1,
         "invalid vector cell falls back to inferred flow");

  const Sequence disoccluded = renderSequence(grid, MotionMode::Disoccluded);
  expect(disoccluded.stats[1].history_suppressed_cells == 1 &&
             disoccluded.stats[1].external_motion_cells == grid.cols * grid.rows - 1 && disoccluded.stats[1].inferred_motion_cells == 0,
         "partial occlusion suppresses only disoccluded history");

  const strok::RenderGrid remapped_grid{.cols = 3, .rows = 2};
  const Sequence remapped = renderSequence(remapped_grid, MotionMode::External);
  expect(remapped.metric.compared_cells == static_cast<std::uint64_t>(remapped_grid.cols * remapped_grid.rows * 2) &&
             remapped.stats[1].external_motion_cells == remapped_grid.cols * remapped_grid.rows,
         "source-to-cell resolution change preserves external motion coverage");
}
