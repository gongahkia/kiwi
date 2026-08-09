#include <strok/renderer.hpp>

#include "renderer.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <vector>

namespace {

constexpr int kFrameWidth = 32;
constexpr int kFrameHeight = 32;
constexpr int kGridCols = 4;
constexpr int kGridRows = 4;

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

struct TemporalStability {
  // Cell churn is changed_cells / compared_cells. Keep its exact numerator and
  // denominator so this renderer-only metric is repeatable and does not imply
  // anything about terminal emission cost.
  std::uint64_t compared_cells = 0;
  std::uint64_t changed_cells = 0;
  std::uint64_t glyph_changes = 0;
  std::uint64_t color_changes = 0;

  bool operator==(const TemporalStability&) const = default;
};

TemporalStability measureChurn(const strok::CellBuffer& previous, const strok::CellBuffer& current) {
  expect(previous.cols() == current.cols() && previous.rows() == current.rows(), "temporal metric dimensions match");
  TemporalStability metric;
  metric.compared_cells = static_cast<std::uint64_t>(current.size());
  for (std::size_t index = 0; index < current.size(); ++index) {
    const strok::Cell& before = previous.cells()[index];
    const strok::Cell& after = current.cells()[index];
    const bool glyph_changed = before.glyph != after.glyph;
    const bool color_changed = before.fg != after.fg || before.bg != after.bg;
    metric.glyph_changes += glyph_changed ? 1U : 0U;
    metric.color_changes += color_changed ? 1U : 0U;
    metric.changed_cells += glyph_changed || color_changed ? 1U : 0U;
  }
  return metric;
}

TemporalStability measureSequence(const std::vector<strok::CellBuffer>& frames) {
  TemporalStability total;
  for (std::size_t index = 1; index < frames.size(); ++index) {
    const TemporalStability frame_metric = measureChurn(frames[index - 1], frames[index]);
    total.compared_cells += frame_metric.compared_cells;
    total.changed_cells += frame_metric.changed_cells;
    total.glyph_changes += frame_metric.glyph_changes;
    total.color_changes += frame_metric.color_changes;
  }
  return total;
}

std::uint8_t textureValue(int x, int y) {
  if (x < 0 || y < 0 || x >= kFrameWidth || y >= kFrameHeight) {
    return 0;
  }
  return static_cast<std::uint8_t>((x * 13 + y * 7 + x * y * 3) % 251);
}

strok::Frame translatedTextureFrame(int offset) {
  strok::Frame frame{
    .w = kFrameWidth,
    .h = kFrameHeight,
    .rgb = {},
  };
  frame.rgb.reserve(static_cast<std::size_t>(kFrameWidth) * static_cast<std::size_t>(kFrameHeight) * 3U);
  for (int y = 0; y < kFrameHeight; ++y) {
    for (int x = 0; x < kFrameWidth; ++x) {
      const std::uint8_t value = textureValue(x - offset, y);
      frame.rgb.insert(frame.rgb.end(), {value, value, value});
    }
  }
  return frame;
}

strok::Frame angledEdgeFrame(int numerator, int denominator) {
  strok::Frame frame{
    .w = kFrameWidth,
    .h = kFrameHeight,
    .rgb = {},
  };
  frame.rgb.reserve(static_cast<std::size_t>(kFrameWidth) * static_cast<std::size_t>(kFrameHeight) * 3U);
  for (int y = 0; y < kFrameHeight; ++y) {
    for (int x = 0; x < kFrameWidth; ++x) {
      const int distance = x * denominator + y * numerator - ((kFrameWidth / 2) * denominator);
      const std::uint8_t value = distance < 0 ? 0U : 255U;
      frame.rgb.insert(frame.rgb.end(), {value, value, value});
    }
  }
  return frame;
}

strok::Frame solidColorFrame(std::uint8_t red, std::uint8_t green, std::uint8_t blue) {
  strok::Frame frame{
    .w = 8,
    .h = 8,
    .rgb = {},
  };
  frame.rgb.reserve(8U * 8U * 3U);
  for (int index = 0; index < 8 * 8; ++index) {
    frame.rgb.insert(frame.rgb.end(), {red, green, blue});
  }
  return frame;
}

struct HistorySequence {
  std::vector<strok::CellBuffer> cells;
  std::vector<strok::RenderStats> stats;
  TemporalStability metric;
};

HistorySequence renderHistorySequence(double glyph_stickiness) {
  strok::RendererConfig config;
  config.cell_aspect = 1.0;
  config.mode = "structure";
  config.edge_threshold = 0.01;
  config.glyph_stickiness = glyph_stickiness;
  const strok::Renderer::CreateResult created = strok::Renderer::create(config, strok::RenderGrid{.cols = kGridCols, .rows = kGridRows});
  expect(created.succeeded(), "history renderer construction");

  HistorySequence sequence;
  for (const int offset : {0, 1, 2}) {
    const strok::RenderResult result = created.renderer->render(translatedTextureFrame(offset));
    expect(result.succeeded(), "history fixture render");
    sequence.cells.push_back(created.renderer->cells());
    sequence.stats.push_back(result.stats);
  }
  sequence.metric = measureSequence(sequence.cells);
  return sequence;
}

strok::CellBuffer renderOrientationSequence(double orient_stickiness, strok::RenderTemporalState* temporal_state) {
  strok::RendererConfig config;
  config.cell_aspect = 1.0;
  config.mode = "structure";
  config.edge_threshold = 0.01;
  config.glyph_stickiness = 0.0;
  config.orient_stickiness = orient_stickiness;
  strok::CellBuffer output;
  expect(strok::renderFrame(angledEdgeFrame(0, 1), U" @", config, strok::RenderGrid{.cols = 1, .rows = 1}, nullptr, &output, temporal_state).succeeded(),
         "orientation first frame");
  expect(output.at(0, 0).glyph == U'|', "orientation fixture starts vertical");
  expect(strok::renderFrame(angledEdgeFrame(1, 2), U" @", config, strok::RenderGrid{.cols = 1, .rows = 1}, nullptr, &output, temporal_state).succeeded(),
         "orientation follow-up frame");
  return output;
}

}  // namespace

int main() {
  const HistorySequence sticky_first = renderHistorySequence(0.05);
  const HistorySequence sticky_second = renderHistorySequence(0.05);
  const HistorySequence unstuck = renderHistorySequence(0.0);
  expect(sticky_first.cells == sticky_second.cells && sticky_first.metric == sticky_second.metric,
         "fixed temporal sequence is repeatable");
  expect(sticky_first.stats[0].optical_flow_blocks == 0 && sticky_first.stats[0].warp_history_cells == 0,
         "first temporal frame has no history");
  expect(sticky_first.stats[1].optical_flow_blocks > 0 && sticky_first.stats[1].warp_history_cells > 0,
         "second temporal frame reuses flow-warped history");
  expect(unstuck.stats[1].optical_flow_blocks == 0 && unstuck.stats[1].warp_history_cells == 0,
         "glyph stickiness enables renderer temporal history");
  expect(sticky_first.metric.compared_cells == static_cast<std::uint64_t>(kGridCols * kGridRows * 2),
         "temporal metric counts every adjacent CellBuffer pair");
  expect(sticky_first.metric.glyph_changes > 0, "temporal metric records glyph churn");
  expect(sticky_first.metric.color_changes > 0, "temporal metric records color churn");

  strok::RenderTemporalState sticky_orientation_state;
  const strok::CellBuffer sticky_orientation = renderOrientationSequence(0.60, &sticky_orientation_state);
  strok::RenderTemporalState unstuck_orientation_state;
  const strok::CellBuffer unstuck_orientation = renderOrientationSequence(0.0, &unstuck_orientation_state);
  expect(sticky_orientation.at(0, 0).glyph == U'|', "orientation stickiness retains near vertical history");
  expect(unstuck_orientation.at(0, 0).glyph == U'/', "orientation fixture changes without history");
  const TemporalStability orientation_metric = measureChurn(sticky_orientation, unstuck_orientation);
  expect(orientation_metric.glyph_changes == 1 && orientation_metric.color_changes == 0,
         "temporal metric separates orientation glyph churn from color churn");

  strok::Renderer::CreateResult color_renderer = strok::Renderer::create(
      strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(color_renderer.succeeded(), "color metric renderer construction");
  expect(color_renderer.renderer->render(solidColorFrame(100, 100, 100)).succeeded(), "color metric first frame");
  const strok::CellBuffer color_first = color_renderer.renderer->cells();
  expect(color_renderer.renderer->render(solidColorFrame(100, 104, 96)).succeeded(), "color metric second frame");
  const TemporalStability color_metric = measureChurn(color_first, color_renderer.renderer->cells());
  expect(color_metric.glyph_changes == 0 && color_metric.color_changes == 1 && color_metric.changed_cells == 1,
         "temporal metric observes color-only CellBuffer churn without terminal output");
}
