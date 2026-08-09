#include <strok/renderer.hpp>

#include <array>
#include <cstddef>
#include <cstdlib>
#include <cstdint>
#include <iostream>

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

strok::CellBuffer render(const strok::ColorImageView& image) {
  strok::Renderer::CreateResult created = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{.cols = 2, .rows = 2});
  expect(created.succeeded(), "renderer construction");
  expect(created.renderer->render(image).succeeded(), "multi-format render");
  return created.renderer->cells();
}

}  // namespace

int main() {
  const std::array<uint8_t, 12> rgb = {
    0, 0, 0, 255, 255, 255,
    255, 0, 0, 0, 0, 255,
  };
  const std::array<uint8_t, 16> rgba = {
    0, 0, 0, 0, 255, 255, 255, 1,
    255, 0, 0, 127, 0, 0, 255, 255,
  };
  const std::array<uint8_t, 16> bgra = {
    0, 0, 0, 0, 255, 255, 255, 1,
    0, 0, 255, 127, 255, 0, 0, 255,
  };
  const std::array<uint8_t, 24> padded_rgba = {
    0, 0, 0, 0, 255, 255, 255, 1, 17, 19, 23, 29,
    255, 0, 0, 127, 0, 0, 255, 255, 31, 37, 41, 43,
  };
  const std::array<uint8_t, 24> padded_bgra = {
    0, 0, 0, 0, 255, 255, 255, 1, 17, 19, 23, 29,
    0, 0, 255, 127, 255, 0, 0, 255, 31, 37, 41, 43,
  };

  const strok::CellBuffer rgb_cells = render(strok::ColorImageView{
    .data = rgb.data(),
    .width = 2,
    .height = 2,
    .row_stride_bytes = 6,
    .pixel_format = strok::ColorPixelFormat::Rgb24,
  });
  const strok::CellBuffer rgba_cells = render(strok::ColorImageView{
    .data = rgba.data(),
    .width = 2,
    .height = 2,
    .row_stride_bytes = 8,
    .pixel_format = strok::ColorPixelFormat::Rgba8,
  });
  const strok::CellBuffer bgra_cells = render(strok::ColorImageView{
    .data = bgra.data(),
    .width = 2,
    .height = 2,
    .row_stride_bytes = 8,
    .pixel_format = strok::ColorPixelFormat::Bgra8,
  });
  const strok::CellBuffer padded_rgba_cells = render(strok::ColorImageView{
    .data = padded_rgba.data(),
    .width = 2,
    .height = 2,
    .row_stride_bytes = 12,
    .pixel_format = strok::ColorPixelFormat::Rgba8,
  });
  const strok::CellBuffer padded_bgra_cells = render(strok::ColorImageView{
    .data = padded_bgra.data(),
    .width = 2,
    .height = 2,
    .row_stride_bytes = 12,
    .pixel_format = strok::ColorPixelFormat::Bgra8,
  });

  expect(sameCells(rgb_cells, rgba_cells), "RGBA8 ignores alpha and preserves RGB reconstruction");
  expect(sameCells(rgb_cells, bgra_cells), "BGRA8 channel order preserves RGB reconstruction");
  expect(sameCells(rgb_cells, padded_rgba_cells), "padded RGBA8 reconstruction");
  expect(sameCells(rgb_cells, padded_bgra_cells), "padded BGRA8 reconstruction");
}
