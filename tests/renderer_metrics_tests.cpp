#include "renderer.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::Frame blackFrame() {
  return strok::Frame{
    .w = 2,
    .h = 2,
    .rgb = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
  };
}

void expectNoChanges(const strok::RenderStats& stats, const char* label) {
  expect(stats.changed_glyphs == 0 && stats.changed_foregrounds == 0 &&
             stats.changed_backgrounds == 0 && stats.changed_cells == 0,
         label);
}

}  // namespace

int main() {
  const strok::RenderGrid grid{.cols = 2, .rows = 2};
  const strok::RendererConfig disabled{.cell_aspect = 1.0};
  strok::CellBuffer disabled_cells;
  const strok::RenderResult disabled_result = strok::renderFrame(blackFrame(), U" @", disabled, grid, nullptr, &disabled_cells);
  expect(disabled_result.succeeded(), "disabled metrics render");
  expectNoChanges(disabled_result.stats, "symbolic metrics remain opt-in");

  const strok::RendererConfig enabled{
    .cell_aspect = 1.0,
    .collect_symbolic_metrics = true,
  };
  strok::CellBuffer cells;
  const strok::RenderResult first = strok::renderFrame(blackFrame(), U" @", enabled, grid, nullptr, &cells);
  expect(first.succeeded() && first.stats.render_ns >= 0, "first metrics render reports renderer latency");
  expect(first.stats.changed_glyphs == 4 && first.stats.changed_foregrounds == 4 &&
             first.stats.changed_backgrounds == 4 && first.stats.changed_cells == 4,
         "first render treats a missing prior CellBuffer as a full symbolic update");

  const strok::RenderResult stable = strok::renderFrame(blackFrame(), U" @", enabled, grid, nullptr, &cells);
  expect(stable.succeeded(), "stable metrics render");
  expectNoChanges(stable.stats, "fixed fixture has stable exact symbolic metrics");

  cells.at(0, 0).glyph = U'X';
  const strok::RenderResult glyph = strok::renderFrame(blackFrame(), U" @", enabled, grid, nullptr, &cells);
  expect(glyph.succeeded() && glyph.stats.changed_glyphs == 1 && glyph.stats.changed_foregrounds == 0 &&
             glyph.stats.changed_backgrounds == 0 && glyph.stats.changed_cells == 1,
         "glyph delta is categorized exactly");

  cells.at(0, 0).fg = strok::Rgb{.r = 1};
  const strok::RenderResult foreground = strok::renderFrame(blackFrame(), U" @", enabled, grid, nullptr, &cells);
  expect(foreground.succeeded() && foreground.stats.changed_glyphs == 0 && foreground.stats.changed_foregrounds == 1 &&
             foreground.stats.changed_backgrounds == 0 && foreground.stats.changed_cells == 1,
         "foreground delta is categorized exactly");

  cells.at(0, 0).bg = strok::Rgb{.g = 1};
  const strok::RenderResult background = strok::renderFrame(blackFrame(), U" @", enabled, grid, nullptr, &cells);
  expect(background.succeeded() && background.stats.changed_glyphs == 0 && background.stats.changed_foregrounds == 0 &&
             background.stats.changed_backgrounds == 1 && background.stats.changed_cells == 1,
         "background delta is categorized exactly");

  strok::CellBuffer enabled_cells;
  const strok::RenderResult enabled_output = strok::renderFrame(blackFrame(), U" @", enabled, grid, nullptr, &enabled_cells);
  expect(enabled_output.succeeded() && enabled_cells == disabled_cells, "metrics collection leaves rendering output unchanged");
}
