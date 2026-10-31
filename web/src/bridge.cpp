#include <strok/renderer.hpp>

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <memory>
#include <string>
#include <vector>

namespace {

std::string last_error;

struct WebRenderer {
  std::unique_ptr<strok::Renderer> renderer;
  std::vector<uint32_t> packed_cells;
};

uint32_t packedColor(strok::Rgb color) {
  return (static_cast<uint32_t>(color.r) << 16U) |
         (static_cast<uint32_t>(color.g) << 8U) | color.b;
}

}  // namespace

// A deliberately small browser adapter. The native SDK and C ABI remain unchanged.
// Each cell is three uint32 values: Unicode scalar, 0xRRGGBB fg, 0xRRGGBB bg.
extern "C" {

const char* strok_web_error() { return last_error.c_str(); }

WebRenderer* strok_web_create(int cols, int rows, int effect, double edge, double contrast, int stable) {
  last_error.clear();
  if (cols < 1 || cols > 160 || rows < 1 || rows > 120 || effect < 0 || effect > 6 ||
      !std::isfinite(edge) || edge < 0.001 || edge > 2.0 ||
      !std::isfinite(contrast) || contrast < 0.0 || contrast > 4.0) {
    last_error = "Invalid browser renderer configuration";
    return nullptr;
  }
  try {
    strok::RendererConfig config;
    config.width = cols;
    config.height = rows;
    config.cell_aspect = 0.5;
    config.mode = "structure";
    config.structure_overlay = "on";
    config.font_path = "/strok/font.otf";
    config.edge_threshold = edge;
    config.contrast = contrast;
    config.glyph_stickiness = stable ? 0.05 : 0.0;
    config.dog_sigma = 0.0;
    switch (effect) {
      case 0: break;
      case 1: config.mode = "luminance"; config.structure_overlay = "off"; break;
      case 2: config.style = "hatch"; break;
      case 3: config.mode = "braille"; config.structure_overlay = "off"; break;
      case 4: config.mode = "halfblock"; config.structure_overlay = "off"; break;
      case 5: config.mode = "luminance"; config.style = "stipple"; config.structure_overlay = "off"; break;
      case 6: config.style = "painterly"; break;
    }
    auto created = strok::Renderer::create(std::move(config), {.cols = cols, .rows = rows});
    if (!created.succeeded()) {
      last_error = created.result.message;
      return nullptr;
    }
    auto state = std::make_unique<WebRenderer>();
    state->renderer = std::move(created.renderer);
    state->packed_cells.reserve(static_cast<std::size_t>(cols) * rows * 3U);
    return state.release();
  } catch (const std::exception& error) {
    last_error = error.what();
  } catch (...) {
    last_error = "Unable to initialize browser renderer";
  }
  return nullptr;
}

void strok_web_destroy(WebRenderer* state) { delete state; }

void strok_web_reset(WebRenderer* state) {
  if (state != nullptr) state->renderer->reset();
}

int strok_web_render(WebRenderer* state, const uint8_t* rgba, int width, int height, int byte_length) {
  last_error.clear();
  if (state == nullptr || rgba == nullptr || width < 1 || height < 1 ||
      width > 1024 || height > 1024 || byte_length != width * height * 4) {
    last_error = "Invalid RGBA frame";
    return 0;
  }
  try {
    const auto result = state->renderer->render(strok::ColorImageView{
      .data = rgba,
      .width = width,
      .height = height,
      .row_stride_bytes = static_cast<std::size_t>(width) * 4U,
      .pixel_format = strok::ColorPixelFormat::Rgba8,
    });
    if (!result.succeeded()) {
      last_error = result.message;
      return 0;
    }
    state->packed_cells.clear();
    for (const auto& cell : state->renderer->cells().cells()) {
      state->packed_cells.push_back(static_cast<uint32_t>(cell.glyph));
      state->packed_cells.push_back(packedColor(cell.fg));
      state->packed_cells.push_back(packedColor(cell.bg));
    }
    return 1;
  } catch (const std::exception& error) {
    last_error = error.what();
  } catch (...) {
    last_error = "Unable to render browser frame";
  }
  return 0;
}

const uint32_t* strok_web_cells(const WebRenderer* state) {
  return state == nullptr ? nullptr : state->packed_cells.data();
}

int strok_web_cell_count(const WebRenderer* state) {
  return state == nullptr ? 0 : static_cast<int>(state->packed_cells.size() / 3U);
}

}  // extern "C"
