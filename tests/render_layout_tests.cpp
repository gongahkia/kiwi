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
  const contourtty::Frame frame{.w = 400, .h = 200};
  const contourtty::TerminalSize terminal{.cols = 80, .rows = 24};

  contourtty::CliOptions options;
  options.width = 200;
  options.height = 100;
  const contourtty::RenderSize explicit_size = contourtty::fitRenderSize(frame, options, terminal);
  expect(explicit_size.cols == 200 && explicit_size.rows == 50, "explicit bounds without fit");

  options.fit = true;
  const contourtty::RenderSize fit_size = contourtty::fitRenderSize(frame, options, terminal);
  expect(fit_size.cols == 80 && fit_size.rows == 20, "fit clamps to terminal");

  const contourtty::RenderOrigin origin = contourtty::centeredOrigin(contourtty::RenderSize{.cols = 40, .rows = 10}, terminal);
  expect(origin.row == 8 && origin.col == 21, "center origin");
}
