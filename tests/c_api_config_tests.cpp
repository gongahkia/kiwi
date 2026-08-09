#include "c_api_config.hpp"

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

}  // namespace

int main() {
  StrokRendererConfig c_config;
  strok_renderer_config_init(&c_config);
  expect(c_config.version == STROK_C_ABI_VERSION, "config initializer sets ABI version");
  expect(c_config.struct_size == sizeof(c_config), "config initializer sets structure size");
  expect(c_config.cell_aspect == 0.5, "config initializer preserves renderer aspect default");
  expect(c_config.mode == STROK_RENDERER_MODE_LUMINANCE, "config initializer preserves renderer mode default");
  expect(c_config.temporal_supersample == 1, "config initializer preserves temporal default");

  StrokRenderGrid c_grid;
  strok_render_grid_init(&c_grid);
  expect(c_grid.version == STROK_C_ABI_VERSION && c_grid.struct_size == sizeof(c_grid), "grid initializer sets ABI header");
  c_grid.cols = 3;
  c_grid.rows = 2;

  const char* graph_passes[] = {"etf", "lic"};
  c_config.presence = STROK_RENDERER_CONFIG_PRESENT_WIDTH |
                      STROK_RENDERER_CONFIG_PRESENT_HEIGHT |
                      STROK_RENDERER_CONFIG_PRESENT_FONT_PATH |
                      STROK_RENDERER_CONFIG_PRESENT_CHARSET |
                      STROK_RENDERER_CONFIG_PRESENT_EDGE_THRESHOLD |
                      STROK_RENDERER_CONFIG_PRESENT_ETF_ITERS;
  c_config.flags = STROK_RENDERER_CONFIG_FLAG_RAMP_SORT |
                   STROK_RENDERER_CONFIG_FLAG_FIT |
                   STROK_RENDERER_CONFIG_FLAG_GPU |
                   STROK_RENDERER_CONFIG_FLAG_LINE_LIGATURES;
  c_config.width = 10;
  c_config.height = 8;
  c_config.mode = STROK_RENDERER_MODE_STRUCTURE;
  c_config.style = STROK_RENDERER_STYLE_FLOW;
  c_config.structure_overlay = STROK_STRUCTURE_OVERLAY_ON;
  c_config.glyph_features = STROK_GLYPH_FEATURES_HOG;
  c_config.font_path = "/tmp/strok-test-font.ttf";
  c_config.charset = " .#";
  c_config.edge_threshold = 0.2;
  c_config.etf_iters = 3;
  c_config.graph_passes = graph_passes;
  c_config.graph_pass_count = 2;

  std::string error;
  const std::optional<strok::RendererConfig> config = strok::rendererConfigFromC(&c_config, &error);
  expect(config.has_value(), "C renderer configuration converts");
  expect(config->width == 10 && config->height == 8, "optional dimensions convert");
  expect(config->mode == "structure" && config->style == "flow", "renderer enums convert");
  expect(config->structure_overlay == "on" && config->glyph_features == "hog", "configuration enums convert");
  expect(config->font_path == c_config.font_path && config->charset == c_config.charset, "borrowed strings copy into C++ configuration");
  expect(config->ramp_sort && config->fit && config->gpu && config->line_ligatures, "renderer flags convert");
  expect(config->graph_passes.size() == 2 && config->graph_passes.at(1) == "lic", "graph pass list copies into C++ configuration");

  const std::optional<strok::RenderGrid> grid = strok::renderGridFromC(&c_grid, &error);
  expect(grid.has_value() && grid->cols == 3 && grid->rows == 2, "C render grid converts");

  c_config.mode = UINT32_C(99);
  expect(!strok::rendererConfigFromC(&c_config, &error).has_value(), "unsupported renderer mode is rejected");
  c_config.mode = STROK_RENDERER_MODE_STRUCTURE;
  c_config.version = UINT32_C(0x00020000);
  expect(!strok::rendererConfigFromC(&c_config, &error).has_value(), "incompatible ABI major is rejected");
  c_config.version = STROK_C_ABI_VERSION;
  c_config.struct_size = sizeof(c_config) - 1U;
  expect(!strok::rendererConfigFromC(&c_config, &error).has_value(), "undersized renderer structure is rejected");
  c_config.struct_size = sizeof(c_config);
  c_config.flags |= UINT32_C(1) << 31;
  expect(!strok::rendererConfigFromC(&c_config, &error).has_value(), "unsupported renderer flags are rejected");
  c_config.flags &= ~(UINT32_C(1) << 31);
  c_config.cell_aspect = 0.0;
  expect(!strok::rendererConfigFromC(&c_config, &error).has_value(), "invalid renderer values are rejected");
  c_config.cell_aspect = 0.5;

  c_grid.cols = 0;
  expect(!strok::renderGridFromC(&c_grid, &error).has_value(), "invalid grid dimensions are rejected");
  c_grid.cols = 3;
  c_grid.version = UINT32_C(0x00020000);
  expect(!strok::renderGridFromC(&c_grid, &error).has_value(), "incompatible grid ABI major is rejected");
}
