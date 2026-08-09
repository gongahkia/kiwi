#include "render_layout.hpp"
#include "terminal_layout.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  const strok::Frame frame{.w = 400, .h = 200};
  const strok::RenderGrid available_grid{.cols = 80, .rows = 24};

  strok::RendererConfig config;
  config.width = 200;
  config.height = 100;
  const strok::RenderGrid explicit_size = strok::fitRenderGrid(frame, config, available_grid);
  expect(explicit_size.cols == 200 && explicit_size.rows == 50, "explicit bounds without fit");

  config.fit = true;
  const strok::RenderGrid fit_size = strok::fitRenderGrid(frame, config, available_grid);
  expect(fit_size.cols == 80 && fit_size.rows == 20, "fit clamps to render grid");

  const strok::RenderGrid direct_size = strok::fitRenderGrid(frame, strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{.cols = 40, .rows = 10});
  expect(direct_size.cols == 20 && direct_size.rows == 10, "direct render grid");

  const strok::TerminalRenderOrigin origin = strok::centeredTerminalOrigin(40, 10, strok::TerminalSize{.cols = 80, .rows = 24});
  expect(origin.row == 8 && origin.col == 21, "center terminal origin");
}
