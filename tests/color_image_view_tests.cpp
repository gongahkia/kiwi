#include <strok/color_image_view.hpp>
#include <strok/renderer.hpp>

#include <array>
#include <cstddef>
#include <cstdlib>
#include <cstdint>
#include <iostream>
#include <limits>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

bool sameCells(const strok::CellBuffer& left, const strok::CellBuffer& right) {
  if (left.cols() != right.cols() || left.rows() != right.rows() || left.size() != right.size()) {
    return false;
  }
  for (std::size_t index = 0; index < left.size(); ++index) {
    const strok::Cell& lhs = left.cells()[index];
    const strok::Cell& rhs = right.cells()[index];
    if (lhs.glyph != rhs.glyph ||
        lhs.fg.r != rhs.fg.r || lhs.fg.g != rhs.fg.g || lhs.fg.b != rhs.fg.b ||
        lhs.bg.r != rhs.bg.r || lhs.bg.g != rhs.bg.g || lhs.bg.b != rhs.bg.b) {
      return false;
    }
  }
  return true;
}

strok::Renderer::CreateResult createRenderer() {
  return strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{.cols = 2, .rows = 2});
}

}  // namespace

int main() {
  const std::array<uint8_t, 16> padded_rgb = {
    0, 0, 0, 255, 255, 255, 19, 23,
    255, 0, 0, 0, 0, 255, 29, 31,
  };
  const strok::ColorImageView padded_view{
    .data = padded_rgb.data(),
    .width = 2,
    .height = 2,
    .row_stride_bytes = 8,
    .pixel_format = strok::ColorPixelFormat::Rgb24,
  };

  strok::Renderer::CreateResult borrowed_renderer = createRenderer();
  expect(borrowed_renderer.succeeded(), "borrowed renderer construction");
  expect(borrowed_renderer.renderer->render(padded_view).succeeded(), "padded RGB24 render");
  const strok::CellBuffer& borrowed_cells = borrowed_renderer.renderer->cells();
  expect(borrowed_cells.at(0, 0).glyph == U' ' && borrowed_cells.at(1, 0).glyph == U'@', "padded RGB24 first row");
  expect(borrowed_cells.at(0, 1).fg.r == 255 && borrowed_cells.at(0, 1).fg.g == 0 && borrowed_cells.at(0, 1).fg.b == 0, "padded RGB24 second row first pixel");
  expect(borrowed_cells.at(1, 1).fg.r == 0 && borrowed_cells.at(1, 1).fg.g == 0 && borrowed_cells.at(1, 1).fg.b == 255, "padded RGB24 second row second pixel");

  const strok::Frame frame{
    .w = 2,
    .h = 2,
    .rgb = {0, 0, 0, 255, 255, 255, 255, 0, 0, 0, 0, 255},
  };
  strok::Renderer::CreateResult frame_renderer = createRenderer();
  expect(frame_renderer.succeeded() && frame_renderer.renderer->render(frame).succeeded(), "legacy Frame render");
  expect(sameCells(borrowed_cells, frame_renderer.renderer->cells()), "borrowed RGB24 matches legacy Frame");

  strok::CellBuffer output(1, 1);
  output.at(0, 0).glyph = U'X';
  const auto expectInvalid = [&](const strok::ColorImageView& image, const char* label) {
    const strok::RenderResult result = borrowed_renderer.renderer->render(image, &output);
    expect(result.status == strok::RenderStatus::InvalidInput, label);
    expect(output.cols() == 1 && output.rows() == 1 && output.at(0, 0).glyph == U'X', "invalid image preserves output");
  };

  expectInvalid(strok::ColorImageView{
                  .data = nullptr,
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = 3,
                  .pixel_format = strok::ColorPixelFormat::Rgb24,
                },
                "null image data");
  expectInvalid(strok::ColorImageView{
                  .data = padded_rgb.data(),
                  .width = 0,
                  .height = 1,
                  .row_stride_bytes = 3,
                  .pixel_format = strok::ColorPixelFormat::Rgb24,
                },
                "invalid image dimensions");
  expectInvalid(strok::ColorImageView{
                  .data = padded_rgb.data(),
                  .width = 2,
                  .height = 1,
                  .row_stride_bytes = 5,
                  .pixel_format = strok::ColorPixelFormat::Rgb24,
                },
                "undersized RGB24 row stride");
  expectInvalid(strok::ColorImageView{
                  .data = padded_rgb.data(),
                  .width = 1,
                  .height = std::numeric_limits<int>::max(),
                  .row_stride_bytes = std::numeric_limits<std::size_t>::max(),
                  .pixel_format = strok::ColorPixelFormat::Rgb24,
                },
                "overflowing RGB24 layout");
  expectInvalid(strok::ColorImageView{
                  .data = padded_rgb.data(),
                  .width = 1,
                  .height = 1,
                  .row_stride_bytes = 3,
                  .pixel_format = static_cast<strok::ColorPixelFormat>(99),
                },
                "unsupported RGB24 format");
}
