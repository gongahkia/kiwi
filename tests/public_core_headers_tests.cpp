#include <strok/cell_buffer.hpp>
#include <strok/frame.hpp>
#include <strok/render.hpp>
#include <strok/renderer_config.hpp>
#include <strok/render_grid.hpp>
#include <strok/render_result.hpp>

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
  strok::CellBuffer cells(2, 1);
  cells.at(1, 0) = strok::Cell{
    .glyph = U'X',
    .fg = strok::Rgb{.r = 12, .g = 34, .b = 56},
    .bg = strok::Rgb{.r = 78, .g = 90, .b = 123},
  };

  expect(cells.cols() == 2 && cells.rows() == 1, "public CellBuffer dimensions");
  expect(cells.at(1, 0).glyph == U'X', "public Cell glyph");
  expect(cells.at(1, 0).fg.g == 34 && cells.at(1, 0).bg.b == 123, "public Cell colors");

  const strok::RendererConfig config;
  expect(config.mode == "luminance" && config.style == "none", "public RendererConfig defaults");

  const strok::RenderGrid grid{.cols = 2, .rows = 1};
  expect(grid.cols == 2 && grid.rows == 1, "public RenderGrid dimensions");

  const strok::RenderResult result;
  expect(result.succeeded() && result.stats.frames == 0, "public RenderResult defaults");

  const strok::Frame frame{.w = 1, .h = 1, .rgb = {0, 0, 0}};
  strok::CellBuffer rendered;
  const strok::RenderResult render_result = strok::renderFrame(frame, U" @", strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{.cols = 1, .rows = 1}, &rendered);
  expect(render_result.succeeded() && rendered.at(0, 0).glyph == U' ', "public render function");
}
