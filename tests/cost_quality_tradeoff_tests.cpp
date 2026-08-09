#include <strok/renderer.hpp>

#include "diff_emitter.hpp"
#include "temporal_stability_metric.hpp"

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

struct TradeOffReport {
  strok::CellBuffer previous;
  strok::CellBuffer current;
  strok::RenderResult render;
  strok_test::TemporalStability symbolic;
  std::size_t emitted_cells = 0;
  std::size_t emitted_bytes = 0;
};

TradeOffReport measureTradeOff(std::optional<double> presentation_cost_weight,
                               std::optional<int64_t> symbolic_update_budget) {
  strok::RendererConfig config;
  config.cell_aspect = 1.0;
  config.mode = "structure";
  config.edge_threshold = 0.01;
  config.glyph_stickiness = 0.05;
  config.temporal_cell_reuse = true;
  config.presentation_cost_weight = presentation_cost_weight;
  config.symbolic_update_budget = symbolic_update_budget;
  const strok::Renderer::CreateResult created = strok::Renderer::create(config, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(created.succeeded(), "cost-quality renderer construction");
  expect(created.renderer->render(splitEdgeFrame(true)).succeeded(), "cost-quality first frame");

  TradeOffReport report{.previous = created.renderer->cells()};
  report.render = created.renderer->render(splitEdgeFrame(false));
  expect(report.render.succeeded(), "cost-quality second frame");
  report.current = created.renderer->cells();
  report.symbolic = strok_test::measureChurn(report.previous, report.current);

  strok::DiffEmitter emitter;
  (void)emitter.emit(report.previous);
  const strok::EmissionResult emitted = emitter.emit(report.current);
  report.emitted_cells = emitted.changed_cells;
  report.emitted_bytes = emitted.bytes.size();
  return report;
}

}  // namespace

int main() {
  const TradeOffReport baseline = measureTradeOff(std::nullopt, std::nullopt);
  const TradeOffReport explicitly_disabled = measureTradeOff(0.0, std::nullopt);
  expect(baseline.previous == explicitly_disabled.previous && baseline.current == explicitly_disabled.current,
         "disabled presentation settings preserve the exact CellBuffer baseline");
  expect(baseline.symbolic.changed_cells == 1 && baseline.symbolic.glyph_changes == 1 &&
             baseline.symbolic.color_changes == 0 && baseline.emitted_cells == 1 && baseline.emitted_bytes > 0,
         "baseline reports independent symbolic churn and ANSI emission");

  const TradeOffReport observed_budget = measureTradeOff(0.0, 1);
  expect(observed_budget.current == baseline.current && observed_budget.render.stats.modeled_symbolic_update_units == 1 &&
             observed_budget.emitted_cells == baseline.emitted_cells && observed_budget.emitted_bytes == baseline.emitted_bytes,
         "unpressured budget measures without changing reconstruction or emission");
  expect(observed_budget.render.stats.modeled_symbolic_update_units != static_cast<int64_t>(observed_budget.emitted_bytes),
         "modeled symbolic units remain distinct from actual ANSI bytes");

  const TradeOffReport constrained_budget = measureTradeOff(0.0, 0);
  expect(constrained_budget.current == constrained_budget.previous &&
             constrained_budget.symbolic.changed_cells == 0 && constrained_budget.symbolic.glyph_changes == 0 &&
             constrained_budget.emitted_cells == 0 && constrained_budget.emitted_bytes == 0,
         "budgeted fixture reduces symbolic churn and actual ANSI emission");
  expect(constrained_budget.render.stats.modeled_symbolic_update_units == 0 &&
             !constrained_budget.render.stats.symbolic_update_budget_exceeded &&
             constrained_budget.render.stats.budget_suppressed_updates == 1 &&
             constrained_budget.render.stats.budget_reconstruction_score_loss > 0.0,
         "budgeted fixture reports modeled cost and reconstruction trade-off separately");
}
