#include "render_layout.hpp"

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
  const strok::TerminalSize terminal{.cols = 80, .rows = 24};

  strok::RendererConfig config;
  config.width = 200;
  config.height = 100;
  const strok::RenderSize explicit_size = strok::fitRenderSize(frame, config, terminal);
  expect(explicit_size.cols == 200 && explicit_size.rows == 50, "explicit bounds without fit");

  config.fit = true;
  const strok::RenderSize fit_size = strok::fitRenderSize(frame, config, terminal);
  expect(fit_size.cols == 80 && fit_size.rows == 20, "fit clamps to terminal");

  const strok::RenderOrigin origin = strok::centeredOrigin(strok::RenderSize{.cols = 40, .rows = 10}, terminal);
  expect(origin.row == 8 && origin.col == 21, "center origin");
}
