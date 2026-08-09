#include <strok/c_api.h>
#include <strok/renderer.hpp>

#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::ColorImageView colorView(const uint8_t* data) {
  return strok::ColorImageView{
    .data = data,
    .width = 2,
    .height = 2,
    .row_stride_bytes = 6,
    .pixel_format = strok::ColorPixelFormat::Rgb24,
  };
}

void expectCellEquals(const StrokCell& actual, const strok::Cell& expected, const char* label) {
  expect(actual.glyph == static_cast<uint32_t>(expected.glyph), label);
  expect(actual.fg_r == expected.fg.r && actual.fg_g == expected.fg.g && actual.fg_b == expected.fg.b, label);
  expect(actual.bg_r == expected.bg.r && actual.bg_g == expected.bg.g && actual.bg_b == expected.bg.b, label);
}

}  // namespace

int main() {
  const std::array<uint8_t, 12> first_pixels = {
    0, 0, 0, 255, 255, 255,
    255, 0, 0, 0, 0, 255,
  };
  const std::array<uint8_t, 12> second_pixels = {
    255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255,
  };

  StrokRendererConfig c_config;
  StrokRenderGrid c_grid;
  StrokRenderer* c_renderer = nullptr;
  strok_renderer_config_init(&c_config);
  strok_render_grid_init(&c_grid);
  c_grid.cols = 2;
  c_grid.rows = 2;
  expect(strok_renderer_create(&c_config, &c_grid, &c_renderer) == STROK_STATUS_SUCCESS && c_renderer != nullptr,
         "C renderer creation");

  int32_t cols = -1;
  int32_t rows = -1;
  expect(strok_renderer_cell_buffer_dimensions(c_renderer, &cols, &rows) == STROK_STATUS_INVALID_ARGUMENT,
         "no output dimensions rejected");
  expect(cols == -1 && rows == -1, "no output dimensions preserve outputs");

  StrokCell cell{.glyph = UINT32_C(0x1234)};
  expect(strok_renderer_cell_buffer_at(c_renderer, 0, 0, &cell) == STROK_STATUS_INVALID_ARGUMENT,
         "no output cell rejected");
  expect(cell.glyph == UINT32_C(0x1234), "no output cell preserves destination");

  StrokColorImageView c_image;
  strok_color_image_view_init(&c_image);
  c_image.data = first_pixels.data();
  c_image.width = 2;
  c_image.height = 2;
  c_image.row_stride_bytes = 6;
  expect(strok_renderer_render_color(c_renderer, &c_image) == STROK_STATUS_SUCCESS, "C first render");
  expect(strok_renderer_cell_buffer_dimensions(c_renderer, &cols, &rows) == STROK_STATUS_SUCCESS && cols > 0 && rows > 0,
         "C output dimensions");

  const strok::Renderer::CreateResult cpp_created = strok::Renderer::create(
      strok::RendererConfig{.cell_aspect = 0.5}, strok::RenderGrid{.cols = 2, .rows = 2});
  expect(cpp_created.succeeded(), "C++ renderer creation");
  expect(cpp_created.renderer->render(colorView(first_pixels.data())).succeeded(), "C++ first render");
  expect(cpp_created.renderer->cells().cols() == cols && cpp_created.renderer->cells().rows() == rows,
         "C and C++ output dimensions match");
  for (int32_t row = 0; row < rows; ++row) {
    for (int32_t col = 0; col < cols; ++col) {
      expect(strok_renderer_cell_buffer_at(c_renderer, col, row, &cell) == STROK_STATUS_SUCCESS, "C cell read");
      expectCellEquals(cell, cpp_created.renderer->cells().at(col, row), "C and C++ cells match");
    }
  }

  const strok::Cell retained_cpp = cpp_created.renderer->cells().at(0, 0);
  expect(strok_renderer_reset(c_renderer) == STROK_STATUS_SUCCESS, "C renderer reset");
  expect(strok_renderer_cell_buffer_at(c_renderer, 0, 0, &cell) == STROK_STATUS_SUCCESS, "cell survives reset");
  expectCellEquals(cell, retained_cpp, "reset retains output");

  c_image.data = nullptr;
  expect(strok_renderer_render_color(c_renderer, &c_image) == STROK_STATUS_INVALID_ARGUMENT, "invalid render rejected");
  expect(strok_renderer_cell_buffer_at(c_renderer, 0, 0, &cell) == STROK_STATUS_SUCCESS, "failed render retains output");
  expectCellEquals(cell, retained_cpp, "failed render retains output value");

  c_image.data = second_pixels.data();
  expect(strok_renderer_render_color(c_renderer, &c_image) == STROK_STATUS_SUCCESS, "C replacement render");
  expect(cpp_created.renderer->render(colorView(second_pixels.data())).succeeded(), "C++ replacement render");
  for (int32_t row = 0; row < rows; ++row) {
    for (int32_t col = 0; col < cols; ++col) {
      expect(strok_renderer_cell_buffer_at(c_renderer, col, row, &cell) == STROK_STATUS_SUCCESS, "C replacement cell read");
      expectCellEquals(cell, cpp_created.renderer->cells().at(col, row), "C and C++ replacement cells match");
    }
  }

  cell.glyph = UINT32_C(0x1234);
  expect(strok_renderer_cell_buffer_at(c_renderer, 2, 0, &cell) == STROK_STATUS_INVALID_ARGUMENT,
         "out of range cell rejected");
  expect(cell.glyph == UINT32_C(0x1234), "out of range cell preserves destination");
  strok_renderer_destroy(c_renderer);
}
