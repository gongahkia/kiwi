#include <strok/render.hpp>

int main() {
  strok::Frame frame{
    .w = 2,
    .h = 2,
    .rgb = {
      0, 0, 0,
      255, 255, 255,
      255, 255, 255,
      0, 0, 0,
    },
  };
  const strok::RendererConfig config{.cell_aspect = 1.0};
  const strok::RenderGrid grid{.cols = 2, .rows = 2};
  strok::CellBuffer cells;
  const strok::RenderResult result = strok::renderFrame(frame, U" @", config, grid, &cells);
  if (!result.succeeded() || cells.cols() != 2 || cells.rows() != 2) {
    return 1;
  }
  const strok::Cell& top_left = cells.at(0, 0);
  return top_left.glyph == U' ' && top_left.fg.r == 0 && top_left.fg.g == 0 && top_left.fg.b == 0 ? 0 : 1;
}
