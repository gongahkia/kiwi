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

strok::Frame solidFrame(std::uint8_t value) {
  constexpr int kWidth = 16;
  constexpr int kHeight = 8;
  strok::Frame frame{
    .w = kWidth,
    .h = kHeight,
    .rgb = {},
  };
  frame.rgb.reserve(static_cast<std::size_t>(kWidth) * static_cast<std::size_t>(kHeight) * 3U);
  for (int index = 0; index < kWidth * kHeight; ++index) {
    frame.rgb.insert(frame.rgb.end(), {value, value, value});
  }
  return frame;
}

struct BudgetedRender {
  strok::CellBuffer cells;
  strok::RenderResult first;
  strok::RenderResult stable;
};

BudgetedRender renderWithBudget(std::optional<int64_t> budget) {
  strok::RendererConfig config;
  config.cell_aspect = 1.0;
  config.symbolic_update_budget = budget;
  const strok::Renderer::CreateResult created = strok::Renderer::create(config, strok::RenderGrid{.cols = 2, .rows = 1});
  expect(created.succeeded(), "symbolic-budget renderer construction");
  BudgetedRender result;
  result.first = created.renderer->render(solidFrame(192));
  expect(result.first.succeeded(), "symbolic-budget first render");
  result.cells = created.renderer->cells();
  result.stable = created.renderer->render(solidFrame(192));
  expect(result.stable.succeeded(), "symbolic-budget stable render");
  return result;
}

}  // namespace

int main() {
  strok::RendererConfig invalid_config;
  invalid_config.symbolic_update_budget = -1;
  expect(!strok::Renderer::create(invalid_config, strok::RenderGrid{.cols = 1, .rows = 1}).succeeded(),
         "negative symbolic update budgets are rejected");

  const BudgetedRender disabled = renderWithBudget(std::nullopt);
  const BudgetedRender zero_budget = renderWithBudget(0);
  const BudgetedRender sufficient_budget = renderWithBudget(2);
  expect(disabled.cells == zero_budget.cells && disabled.cells == sufficient_budget.cells,
         "budget observation preserves the baseline CellBuffer");
  expect(disabled.first.stats.modeled_symbolic_update_units == 0 &&
             !disabled.first.stats.symbolic_update_budget_exceeded,
         "disabled budget leaves pressure reporting inactive");
  expect(zero_budget.first.stats.modeled_symbolic_update_units == 2 &&
             zero_budget.first.stats.symbolic_update_budget_exceeded,
         "zero budget reports first-frame symbolic pressure");
  expect(sufficient_budget.first.stats.modeled_symbolic_update_units == 2 &&
             !sufficient_budget.first.stats.symbolic_update_budget_exceeded,
         "sufficient budget reports the modeled update set as met");
  expect(zero_budget.stable.stats.modeled_symbolic_update_units == 0 &&
             !zero_budget.stable.stats.symbolic_update_budget_exceeded,
         "stable frame meets the configured budget without terminal emission");
}
