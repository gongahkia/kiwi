#include <strok/renderer_config.hpp>

#include "cli.hpp"
#include "renderer.hpp"
#include "structure_overlay.hpp"

#include <cstdlib>
#include <iostream>
#include <string>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

bool sameCells(const strok::CellBuffer& left, const strok::CellBuffer& right) {
  if (left.cols() != right.cols() || left.rows() != right.rows()) {
    return false;
  }
  for (std::size_t index = 0; index < left.cells().size(); ++index) {
    const strok::Cell& lhs = left.cells()[index];
    const strok::Cell& rhs = right.cells()[index];
    if (lhs.glyph != rhs.glyph || lhs.fg.r != rhs.fg.r || lhs.fg.g != rhs.fg.g || lhs.fg.b != rhs.fg.b ||
        lhs.bg.r != rhs.bg.r || lhs.bg.g != rhs.bg.g || lhs.bg.b != rhs.bg.b) {
      return false;
    }
  }
  return true;
}

}  // namespace

int main() {
  strok::CliOptions options;
  options.width = 80;
  options.height = 24;
  options.cell_aspect = 0.75;
  options.mode = "structure";
  options.style = "hatch";
  options.structure_overlay = "on";
  options.glyph_features = "sdf";
  options.charset = "braille";
  options.edge_threshold = 0.2;
  options.edge_strength = 0.6;
  options.dog_sigma = 0.5;
  options.dog_sigma2 = 1.5;
  options.dog_threshold = 0.04;
  options.etf_iters = 3;
  options.lic_length = 7;
  options.posterize = 5;
  options.contrast = 0.1;
  options.glyph_stickiness = 0.2;
  options.orient_stickiness = 0.3;
  options.temporal_supersample = 4;
  options.fit = true;
  options.gpu = true;
  options.line_ligatures = true;
  options.graph_passes = {"etf", "lic"};

  const strok::RendererConfig config = strok::rendererConfigFromCliOptions(options);
  expect(config.width == options.width && config.height == options.height && config.cell_aspect == options.cell_aspect, "grid configuration conversion");
  expect(config.mode == options.mode && config.style == options.style && config.structure_overlay == options.structure_overlay, "mode configuration conversion");
  expect(config.glyph_features == options.glyph_features && config.charset == options.charset, "glyph configuration conversion");
  expect(config.edge_threshold == options.edge_threshold && config.edge_strength == options.edge_strength, "edge configuration conversion");
  expect(config.dog_sigma == options.dog_sigma && config.dog_sigma2 == options.dog_sigma2 && config.dog_threshold == options.dog_threshold, "DoG configuration conversion");
  expect(config.etf_iters == options.etf_iters && config.lic_length == options.lic_length && config.posterize == options.posterize, "style configuration conversion");
  expect(config.contrast == options.contrast && config.glyph_stickiness == options.glyph_stickiness && config.orient_stickiness == options.orient_stickiness, "temporal configuration conversion");
  expect(config.temporal_supersample == options.temporal_supersample && config.fit == options.fit && config.gpu == options.gpu && config.line_ligatures == options.line_ligatures, "boolean configuration conversion");
  expect(config.graph_passes == options.graph_passes, "graph configuration conversion");
  expect(strok::structureOverlayEnabled(config), "structure overlay configuration");
  expect(strok::dumpRenderGraph(config) == strok::dumpRenderGraph(options), "render graph adapter parity");

  const strok::Frame frame{
    .w = 2,
    .h = 2,
    .rgb = {0, 0, 0, 255, 255, 255, 128, 128, 128, 64, 64, 64},
  };
  const strok::TerminalSize terminal{.cols = 2, .rows = 2};
  strok::CliOptions render_options;
  render_options.cell_aspect = 1.0;
  strok::CellBuffer legacy_cells;
  strok::CellBuffer config_cells;
  strok::renderFrame(frame, U" @", render_options, terminal, nullptr, &legacy_cells);
  strok::renderFrame(frame, U" @", strok::rendererConfigFromCliOptions(render_options), terminal, nullptr, &config_cells);
  expect(sameCells(legacy_cells, config_cells), "render adapter parity");
}
