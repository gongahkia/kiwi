#include <strok/renderer.hpp>

#include <cstdlib>
#include <cstddef>
#include <cstdint>
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

strok::Frame structureFrame() {
  strok::Frame frame;
  frame.w = 8;
  frame.h = 8;
  frame.rgb.resize(8U * 8U * 3U);
  for (int row = 0; row < frame.h; ++row) {
    for (int column = 0; column < frame.w; ++column) {
      const uint8_t value = column < frame.w / 2 ? 0 : 255;
      const std::size_t index = (static_cast<std::size_t>(row) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(column)) * 3U;
      frame.rgb[index] = value;
      frame.rgb[index + 1U] = value;
      frame.rgb[index + 2U] = value;
    }
  }
  return frame;
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
  expect(first.stats.graph_topology_builds == 0 && first.stats.graph_topology_reuses == 1, "renderer reuses graph topology");
  expect(cells.cols() == 2 && cells.rows() == 2 && cells.at(0, 0).glyph == U' ', "renderer output");

  created.renderer->reset();
  const strok::RenderResult second = created.renderer->render(frame(), &cells);
  expect(second.status == strok::RenderStatus::Success && second.stats.frames == 1 && second.stats.cells == 4, "renderer reset render");
  expect(second.stats.graph_topology_builds == 0 && second.stats.graph_topology_reuses == 1, "renderer retains topology across reset");

  const strok::RenderResult owned = created.renderer->render(frame());
  expect(owned.succeeded() && created.renderer->cells().cols() == 2 && created.renderer->cells().rows() == 2, "renderer owned cells");
  const strok::CellBuffer cells_before_reset = created.renderer->cells();
  created.renderer->reset();
  expect(created.renderer->cells() == cells_before_reset, "reset preserves owned cells");

  const strok::Renderer::CreateResult gpu_created = strok::Renderer::create(
    strok::RendererConfig{.cell_aspect = 1.0, .gpu = true}, grid);
  expect(gpu_created.succeeded(), "GPU renderer construction");
  const strok::RenderResult gpu_result = gpu_created.renderer->render(frame());
  expect(gpu_result.succeeded(), "GPU renderer uses its owned backend or CPU fallback");
  expect(gpu_result.stats.attempted_backend == strok::RenderBackend::Auto ||
             gpu_result.stats.attempted_backend == strok::RenderBackend::Metal ||
             gpu_result.stats.attempted_backend == strok::RenderBackend::Vulkan,
         "GPU renderer reports the attempted backend");
  if (gpu_result.stats.selected_backend == strok::RenderBackend::Cpu) {
    expect(gpu_result.stats.executed_backend == strok::RenderBackend::Cpu && gpu_result.stats.backend_fallback,
           "GPU renderer reports explicit CPU fallback");
  }

  const strok::RendererConfig structure_config{
    .cell_aspect = 1.0,
    .mode = "structure",
    .edge_threshold = 0.01,
    .glyph_stickiness = 0.0,
  };
  const strok::RenderGrid structure_grid{.cols = 4, .rows = 4};
  const strok::Frame structure_frame = structureFrame();
  strok::Renderer::CreateResult cpu_structure = strok::Renderer::create(structure_config, structure_grid);
  expect(cpu_structure.succeeded(), "CPU structure renderer construction");
  const strok::RenderResult cpu_structure_result = cpu_structure.renderer->render(structure_frame);
  expect(cpu_structure_result.succeeded(), "CPU structure render");
  const strok::CellBuffer cpu_structure_cells = cpu_structure.renderer->cells();

  strok::RendererConfig gpu_structure_config = structure_config;
  gpu_structure_config.gpu = true;
  strok::Renderer::CreateResult gpu_structure = strok::Renderer::create(gpu_structure_config, structure_grid);
  expect(gpu_structure.succeeded(), "GPU structure renderer construction");
  const strok::RenderResult first_gpu_structure = gpu_structure.renderer->render(structure_frame);
  expect(first_gpu_structure.succeeded(), "first GPU structure render");
  const strok::CellBuffer first_gpu_structure_cells = gpu_structure.renderer->cells();
  const strok::RenderResult second_gpu_structure = gpu_structure.renderer->render(structure_frame);
  expect(second_gpu_structure.succeeded(), "repeated GPU structure render");
  expect(first_gpu_structure.stats.graph_topology_reuses == 1 && second_gpu_structure.stats.graph_topology_reuses == 1,
         "GPU structure renderer reuses graph topology");
  expect(first_gpu_structure.stats.selected_backend == second_gpu_structure.stats.selected_backend,
         "GPU structure renderer retains selected backend");
  expect(first_gpu_structure_cells == cpu_structure_cells && gpu_structure.renderer->cells() == cpu_structure_cells,
         "CPU and GPU-requested structure output parity");
  if (first_gpu_structure.stats.selected_backend == strok::RenderBackend::Cpu) {
    expect(first_gpu_structure.stats.backend_fallback && first_gpu_structure.stats.executed_backend == strok::RenderBackend::Cpu,
           "GPU structure renderer reports CPU fallback");
  } else {
    expect(first_gpu_structure.stats.executed_backend == first_gpu_structure.stats.selected_backend &&
               second_gpu_structure.stats.executed_backend == second_gpu_structure.stats.selected_backend,
           "available GPU executes structure analysis on repeated renders");
  }
  gpu_structure.renderer->reset();
  const strok::RenderResult reset_gpu_structure = gpu_structure.renderer->render(structure_frame);
  expect(reset_gpu_structure.succeeded() && reset_gpu_structure.stats.selected_backend == first_gpu_structure.stats.selected_backend &&
             gpu_structure.renderer->cells() == cpu_structure_cells,
         "GPU structure renderer reset preserves backend lifecycle and parity");

  strok::Renderer::CreateResult custom_charset = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0, .charset = "binary"}, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(custom_charset.succeeded(), "custom charset construction");
  expect(custom_charset.renderer->render(whiteFrame()).succeeded() && custom_charset.renderer->cells().at(0, 0).glyph == U'1', "custom charset render");

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
