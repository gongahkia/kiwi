#include <strok/renderer.hpp>

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <optional>

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

strok::Frame whiteFrame() {
  return strok::Frame{
    .w = 1,
    .h = 1,
    .rgb = {255, 255, 255},
  };
}

std::optional<std::filesystem::path> firstExistingFont() {
  for (const char* path : {
         "/System/Library/Fonts/SFNSMono.ttf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
         "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf",
         "/usr/share/fonts/source-foundry-hack-fonts/Hack-Regular.ttf",
       }) {
    if (std::filesystem::exists(path)) {
      return std::filesystem::path(path);
    }
  }
  return std::nullopt;
}

}  // namespace

int main() {
  const strok::RenderGrid grid{.cols = 2, .rows = 2};

  const strok::Renderer::CreateResult invalid = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 0.0}, grid);
  expect(!invalid.succeeded() && invalid.result.status == strok::RenderStatus::InvalidConfiguration, "invalid construction result");

  const strok::Renderer::CreateResult invalid_grid = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{});
  expect(!invalid_grid.succeeded() && invalid_grid.result.status == strok::RenderStatus::InvalidConfiguration, "invalid grid result");

  const strok::Renderer::CreateResult invalid_ramp_sort = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0, .ramp_sort = true}, grid);
  expect(!invalid_ramp_sort.succeeded() && invalid_ramp_sort.result.status == strok::RenderStatus::InvalidConfiguration, "ramp sort requires font");

  strok::Renderer::CreateResult created = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0}, grid);
  expect(created.succeeded(), "renderer construction");

  strok::CellBuffer cells;
  const strok::RenderResult first = created.renderer->render(frame(), &cells);
  expect(first.status == strok::RenderStatus::Success && first.stats.frames == 1 && first.stats.cells == 4, "renderer first render");
  expect(cells.cols() == 2 && cells.rows() == 2 && cells.at(0, 0).glyph == U' ', "renderer output");

  created.renderer->reset();
  const strok::RenderResult second = created.renderer->render(frame(), &cells);
  expect(second.status == strok::RenderStatus::Success && second.stats.frames == 1 && second.stats.cells == 4, "renderer reset render");

  strok::Renderer::CreateResult custom_charset = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0, .charset = "binary"}, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(custom_charset.succeeded(), "custom charset construction");
  expect(custom_charset.renderer->render(whiteFrame(), &cells).succeeded() && cells.at(0, 0).glyph == U'1', "custom charset render");

  if (const std::optional<std::filesystem::path> font_path = firstExistingFont(); font_path.has_value()) {
    const strok::Renderer::CreateResult font_renderer = strok::Renderer::create(strok::RendererConfig{
                                                                                   .cell_aspect = 1.0,
                                                                                   .font_path = font_path->string(),
                                                                                   .ramp_sort = true,
                                                                                 },
                                                                                 grid);
    expect(font_renderer.succeeded(), "custom font construction");
    expect(font_renderer.renderer->render(frame(), &cells).succeeded(), "custom font render");
  }
}
