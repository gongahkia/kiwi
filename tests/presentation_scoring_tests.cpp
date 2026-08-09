#include <strok/renderer.hpp>

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <optional>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::Frame splitEdgeFrame(bool vertical) {
  constexpr int kWidth = 32;
  constexpr int kHeight = 32;
  strok::Frame frame{
    .w = kWidth,
    .h = kHeight,
    .rgb = {},
  };
  frame.rgb.reserve(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight) * 3U);
  for (int y = 0; y < kHeight; ++y) {
    for (int x = 0; x < kWidth; ++x) {
      const std::uint8_t value = (vertical ? x < kWidth / 2 : y < kHeight / 2) ? 0U : 255U;
      frame.rgb.insert(frame.rgb.end(), {value, value, value});
    }
  }
  return frame;
}

struct SequenceResult {
  strok::CellBuffer previous;
  strok::CellBuffer current;
  strok::RenderResult result;
};

SequenceResult renderSequence(std::optional<double> presentation_cost_weight) {
  strok::RendererConfig config;
  config.cell_aspect = 1.0;
  config.mode = "structure";
  config.edge_threshold = 0.01;
  config.glyph_stickiness = 0.05;
  config.temporal_cell_reuse = true;
  config.presentation_cost_weight = presentation_cost_weight;
  const strok::Renderer::CreateResult created = strok::Renderer::create(config, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(created.succeeded(), "presentation-scoring renderer construction");
  expect(created.renderer->render(splitEdgeFrame(true)).succeeded(), "presentation-scoring first frame");
  SequenceResult sequence{.previous = created.renderer->cells()};
  sequence.result = created.renderer->render(splitEdgeFrame(false));
  expect(sequence.result.succeeded(), "presentation-scoring second frame");
  sequence.current = created.renderer->cells();
  return sequence;
}

}  // namespace

int main() {
  strok::RendererConfig invalid_config;
  invalid_config.presentation_cost_weight = -0.01;
  expect(!strok::Renderer::create(invalid_config, strok::RenderGrid{.cols = 1, .rows = 1}).succeeded(),
         "negative presentation weights are rejected");

  const SequenceResult baseline = renderSequence(std::nullopt);
  const SequenceResult explicitly_disabled = renderSequence(0.0);
  expect(baseline.current == explicitly_disabled.current,
         "disabled presentation scoring preserves the baseline CellBuffer");
  expect(baseline.result.stats.temporal_cell_candidate_cells == 1 &&
             baseline.result.stats.temporal_cell_reused_cells == 0 &&
             baseline.result.stats.temporal_candidate_presentation_cost == 0.0,
         "disabled presentation scoring records no cost term");

  const SequenceResult presentation_aware = renderSequence(0.01);
  expect(presentation_aware.result.stats.temporal_cell_candidate_cells == 1 &&
             presentation_aware.result.stats.temporal_cell_reused_cells == 1,
         "presentation scoring retains the lower-churn temporal candidate");
  expect(presentation_aware.current == presentation_aware.previous && presentation_aware.current != baseline.current,
         "presentation scoring changes the controlled candidate choice");
  expect(presentation_aware.result.stats.temporal_candidate_reconstruction_score > 0.0 &&
             presentation_aware.result.stats.temporal_candidate_presentation_cost > 0.0 &&
             presentation_aware.result.stats.temporal_candidate_temporal_score == 0.0,
         "presentation scoring exposes reconstruction, temporal, and cost diagnostics");
}
