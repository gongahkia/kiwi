#include <strok/renderer.hpp>

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::Frame frame() {
  return strok::Frame{
    .w = 2,
    .h = 2,
    .rgb = {0, 0, 0, 255, 255, 255, 128, 128, 128, 64, 64, 64},
  };
}

}  // namespace

int main() {
  const strok::RenderGrid grid{.cols = 2, .rows = 2};

  const strok::Renderer::CreateResult invalid = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 0.0}, grid);
  expect(!invalid.succeeded() && invalid.result.status == strok::RenderStatus::InvalidConfiguration, "invalid construction result");

  const strok::Renderer::CreateResult invalid_grid = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{});
  expect(!invalid_grid.succeeded() && invalid_grid.result.status == strok::RenderStatus::InvalidConfiguration, "invalid grid result");

  strok::Renderer::CreateResult created = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0}, grid);
  expect(created.succeeded(), "renderer construction");

  strok::CellBuffer cells;
  const strok::RenderResult first = created.renderer->render(frame(), U" @", &cells);
  expect(first.status == strok::RenderStatus::Success && first.stats.frames == 1 && first.stats.cells == 4, "renderer first render");
  expect(cells.cols() == 2 && cells.rows() == 2 && cells.at(0, 0).glyph == U' ', "renderer output");

  created.renderer->reset();
  const strok::RenderResult second = created.renderer->render(frame(), U" @", &cells);
  expect(second.status == strok::RenderStatus::Success && second.stats.frames == 1 && second.stats.cells == 4, "renderer reset render");
}
