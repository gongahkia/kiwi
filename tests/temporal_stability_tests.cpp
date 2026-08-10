#include <strok/renderer.hpp>

#include "renderer.hpp"
#include "temporal_stability_metric.hpp"

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

strok::Frame splitEdgeFrame(bool vertical) {
  strok::Frame frame{
    .w = kFrameWidth,
    .h = kFrameHeight,
    .rgb = {},
  };
  frame.rgb.reserve(static_cast<std::size_t>(kFrameWidth) * static_cast<std::size_t>(kFrameHeight) * 3U);
  for (int y = 0; y < kFrameHeight; ++y) {
    for (int x = 0; x < kFrameWidth; ++x) {
      const std::uint8_t value = (vertical ? x < kFrameWidth / 2 : y < kFrameHeight / 2) ? 0U : 255U;
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
  strok_test::TemporalStability metric;
};

HistorySequence renderHistorySequence(double glyph_stickiness, bool temporal_cell_reuse = false) {
  strok::RendererConfig config;
  config.cell_aspect = 1.0;
  config.mode = "structure";
  config.edge_threshold = 0.01;
  config.glyph_stickiness = glyph_stickiness;
  config.temporal_cell_reuse = temporal_cell_reuse;
  const strok::Renderer::CreateResult created = strok::Renderer::create(config, strok::RenderGrid{.cols = kGridCols, .rows = kGridRows});
  expect(created.succeeded(), "history renderer construction");

  HistorySequence sequence;
  for (const int offset : {0, 1, 2}) {
    const strok::RenderResult result = created.renderer->render(translatedTextureFrame(offset));
    expect(result.succeeded(), "history fixture render");
    sequence.cells.push_back(created.renderer->cells());
    sequence.stats.push_back(result.stats);
  }
  sequence.metric = strok_test::measureSequence(sequence.cells);
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
  strok::RendererConfig retaining_candidate_config;
  retaining_candidate_config.cell_aspect = 1.0;
  retaining_candidate_config.mode = "structure";
  retaining_candidate_config.edge_threshold = 0.01;
  retaining_candidate_config.glyph_stickiness = 1.0;
  retaining_candidate_config.temporal_cell_reuse = true;
  const strok::Renderer::CreateResult retaining_candidate_renderer = strok::Renderer::create(
    retaining_candidate_config, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(retaining_candidate_renderer.succeeded() && retaining_candidate_renderer.renderer->render(splitEdgeFrame(true)).succeeded(),
         "retaining candidate renderer starts a sequence");
  const strok::Cell retained_cell = retaining_candidate_renderer.renderer->cells().at(0, 0);
  const strok::RenderResult retained_candidate = retaining_candidate_renderer.renderer->render(splitEdgeFrame(false));
  expect(retained_candidate.succeeded() && retained_candidate.stats.temporal_cell_candidate_cells == 1 &&
             retained_candidate.stats.temporal_cell_reused_cells == 1,
         "near-tied temporal candidates can retain their full prior CellBuffer value");
  expect(retaining_candidate_renderer.renderer->cells().at(0, 0) == retained_cell,
         "temporal reuse retains the prior glyph and colors together");

  strok::RendererConfig glyph_history_config;
  glyph_history_config.cell_aspect = 1.0;
  glyph_history_config.mode = "structure";
  glyph_history_config.edge_threshold = 0.01;
  glyph_history_config.glyph_stickiness = 1.0;
  glyph_history_config.temporal_cell_reuse = false;
  const strok::Renderer::CreateResult glyph_history_renderer = strok::Renderer::create(
    glyph_history_config, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(glyph_history_renderer.succeeded() && glyph_history_renderer.renderer->render(splitEdgeFrame(true)).succeeded(),
         "glyph history renderer starts a sequence");
  const char32_t previous_glyph = glyph_history_renderer.renderer->cells().at(0, 0).glyph;
  expect(previous_glyph != U' ', "glyph history fixture starts with a structure glyph");
  const strok::RenderResult glyph_history_followup = glyph_history_renderer.renderer->render(splitEdgeFrame(false));
  expect(glyph_history_followup.succeeded() && glyph_history_followup.stats.optical_flow_blocks > 0 &&
             glyph_history_followup.stats.warp_history_cells > 0,
         "glyph history follow-up warps optical-flow history");
  expect(glyph_history_followup.stats.temporal_cell_candidate_cells == 0 && glyph_history_followup.stats.temporal_cell_reused_cells == 0,
         "glyph history stabilization does not require full-cell reuse");
  expect(glyph_history_renderer.renderer->cells().at(0, 0).glyph == previous_glyph,
         "glyph history retains the prior non-space glyph without full-cell reuse");

  retaining_candidate_config.glyph_stickiness = 0.05;
  const strok::Renderer::CreateResult rejected_candidate_renderer = strok::Renderer::create(
    retaining_candidate_config, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(rejected_candidate_renderer.succeeded() && rejected_candidate_renderer.renderer->render(splitEdgeFrame(true)).succeeded(),
         "rejected candidate renderer starts a sequence");
  const strok::RenderResult rejected_candidate = rejected_candidate_renderer.renderer->render(splitEdgeFrame(false));
  expect(rejected_candidate.succeeded() && rejected_candidate.stats.temporal_cell_candidate_cells == 1 &&
             rejected_candidate.stats.temporal_cell_reused_cells == 0,
         "current shape scoring rejects temporal candidates outside the stickiness margin");

  strok::RendererConfig reset_candidate_config;
  reset_candidate_config.cell_aspect = 1.0;
  reset_candidate_config.mode = "structure";
  reset_candidate_config.edge_threshold = 0.01;
  reset_candidate_config.temporal_cell_reuse = true;
  const strok::Renderer::CreateResult reset_candidate_renderer = strok::Renderer::create(
    reset_candidate_config, strok::RenderGrid{.cols = kGridCols, .rows = kGridRows});
  expect(reset_candidate_renderer.succeeded() && reset_candidate_renderer.renderer->render(translatedTextureFrame(0)).succeeded(),
         "candidate reset renderer starts a sequence");
  reset_candidate_renderer.renderer->reset();
  const strok::RenderResult after_candidate_reset = reset_candidate_renderer.renderer->render(translatedTextureFrame(1));
  expect(after_candidate_reset.succeeded() && after_candidate_reset.stats.temporal_cell_candidate_cells == 0,
         "reset clears prior CellBuffer candidates");

  strok::RenderTemporalState sticky_orientation_state;
  const strok::CellBuffer sticky_orientation = renderOrientationSequence(0.60, &sticky_orientation_state);
  strok::RenderTemporalState unstuck_orientation_state;
  const strok::CellBuffer unstuck_orientation = renderOrientationSequence(0.0, &unstuck_orientation_state);
  expect(sticky_orientation.at(0, 0).glyph == U'|', "orientation stickiness retains near vertical history");
  expect(unstuck_orientation.at(0, 0).glyph == U'/', "orientation fixture changes without history");
  const strok_test::TemporalStability orientation_metric = strok_test::measureChurn(sticky_orientation, unstuck_orientation);
  expect(orientation_metric.glyph_changes == 1 && orientation_metric.color_changes == 0,
         "temporal metric separates orientation glyph churn from color churn");

  strok::Renderer::CreateResult color_renderer = strok::Renderer::create(
      strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(color_renderer.succeeded(), "color metric renderer construction");
  expect(color_renderer.renderer->render(solidColorFrame(100, 100, 100)).succeeded(), "color metric first frame");
  const strok::CellBuffer color_first = color_renderer.renderer->cells();
  expect(color_renderer.renderer->render(solidColorFrame(100, 104, 96)).succeeded(), "color metric second frame");
  const strok_test::TemporalStability color_metric = strok_test::measureChurn(color_first, color_renderer.renderer->cells());
  expect(color_metric.glyph_changes == 0 && color_metric.color_changes == 1 && color_metric.changed_cells == 1,
         "temporal metric observes color-only CellBuffer churn without terminal output");
}
