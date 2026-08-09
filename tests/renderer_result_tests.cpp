#include <strok/render_result.hpp>

#include "gpu_sobel.hpp"
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

strok::Frame validFrame() {
  return strok::Frame{
    .w = 2,
    .h = 2,
    .rgb = {0, 0, 0, 255, 255, 255, 128, 128, 128, 64, 64, 64},
  };
}

}  // namespace

int main() {
  const strok::RendererConfig config{.cell_aspect = 1.0};
  const strok::RenderGrid grid{.cols = 2, .rows = 2};

  strok::CellBuffer cells;
  const strok::RenderResult success = strok::renderFrame(validFrame(), U" @", config, grid, nullptr, &cells);
  expect(success.status == strok::RenderStatus::Success && success.succeeded(), "successful render status");
  expect(success.stats.frames == 1 && success.stats.cells == 4 && success.stats.render_ns >= 0, "successful render statistics");
  expect(cells.cols() == 2 && cells.rows() == 2, "successful render output");

  cells.at(0, 0).glyph = U'X';
  const strok::Frame invalid_frame{.w = 2, .h = 2, .rgb = {0, 0, 0}};
  const strok::RenderResult invalid_input = strok::renderFrame(invalid_frame, U" @", config, grid, nullptr, &cells);
  expect(invalid_input.status == strok::RenderStatus::InvalidInput && !invalid_input.succeeded(), "invalid frame status");
  expect(cells.at(0, 0).glyph == U'X', "invalid input preserves output");

  const strok::RendererConfig invalid_config{.cell_aspect = 0.0};
  const strok::RenderResult invalid_configuration = strok::renderFrame(validFrame(), U" @", invalid_config, grid, nullptr, &cells);
  expect(invalid_configuration.status == strok::RenderStatus::InvalidConfiguration && !invalid_configuration.succeeded(), "invalid configuration status");
  expect(cells.at(0, 0).glyph == U'X', "invalid configuration preserves output");

  strok::RendererConfig gpu_config = config;
  gpu_config.gpu = true;
  const strok::RenderResult gpu_result = strok::renderFrame(validFrame(), U" @", gpu_config, grid, nullptr, &cells);
  expect(gpu_result.succeeded(), "GPU request remains recoverable");
  if (!strok::gpuSobelAvailable()) {
    expect(gpu_result.status == strok::RenderStatus::BackendFallback, "GPU fallback status");
  }
}
