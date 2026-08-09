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

SequenceResult renderSequence(std::optional<int64_t> budget) {
  strok::RendererConfig config;
  config.cell_aspect = 1.0;
  config.mode = "structure";
  config.edge_threshold = 0.01;
  config.glyph_stickiness = 0.05;
  config.temporal_cell_reuse = true;
  config.symbolic_update_budget = budget;
  const strok::Renderer::CreateResult created = strok::Renderer::create(config, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(created.succeeded(), "budget-selection renderer construction");
  expect(created.renderer->render(splitEdgeFrame(true)).succeeded(), "budget-selection first frame");
  SequenceResult sequence{.previous = created.renderer->cells()};
  sequence.result = created.renderer->render(splitEdgeFrame(false));
  expect(sequence.result.succeeded(), "budget-selection pressured frame");
  sequence.current = created.renderer->cells();
  return sequence;
}

}  // namespace

int main() {
  const SequenceResult baseline = renderSequence(std::nullopt);
  const SequenceResult sufficient_budget = renderSequence(1);
  expect(baseline.current == sufficient_budget.current && baseline.current != baseline.previous,
         "unpressured budget preserves the reconstruction baseline");
  expect(sufficient_budget.result.stats.modeled_symbolic_update_units == 1 &&
             !sufficient_budget.result.stats.symbolic_update_budget_exceeded &&
             sufficient_budget.result.stats.budget_suppressed_updates == 0,
         "sufficient budget keeps the baseline candidate set");

  const SequenceResult constrained_budget = renderSequence(0);
  expect(constrained_budget.current == constrained_budget.previous && constrained_budget.current != baseline.current,
         "budget pressure retains a valid lower-churn temporal candidate");
  expect(constrained_budget.result.stats.modeled_symbolic_update_units == 0 &&
             !constrained_budget.result.stats.symbolic_update_budget_exceeded &&
             constrained_budget.result.stats.budget_suppressed_updates == 1 &&
             constrained_budget.result.stats.budget_reconstruction_score_loss > 0.0,
         "budget policy reports the churn and reconstruction trade-off");
}
