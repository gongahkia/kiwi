#include <strok/cell_buffer.hpp>
#include <strok/color_image_view.hpp>
#include <strok/depth_image_view.hpp>
#include <strok/frame.hpp>
#include <strok/render.hpp>
#include <strok/renderer.hpp>
#include <strok/renderer_config.hpp>
#include <strok/render_grid.hpp>
#include <strok/render_result.hpp>

#include <cstdlib>
#include <iostream>
#include <optional>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  strok::CellBuffer cells(2, 1);
  cells.at(1, 0) = strok::Cell{
    .glyph = U'X',
    .fg = strok::Rgb{.r = 12, .g = 34, .b = 56},
    .bg = strok::Rgb{.r = 78, .g = 90, .b = 123},
  };

  expect(cells.cols() == 2 && cells.rows() == 1, "public CellBuffer dimensions");
  expect(cells.at(1, 0).glyph == U'X', "public Cell glyph");
  expect(cells.at(1, 0).fg.g == 34 && cells.at(1, 0).bg.b == 123, "public Cell colors");

  const strok::RendererConfig config;
  expect(config.mode == "luminance" && config.style == "none", "public RendererConfig defaults");

  const strok::RenderGrid grid{.cols = 2, .rows = 1};
  expect(grid.cols == 2 && grid.rows == 1, "public RenderGrid dimensions");

  const strok::RenderResult result;
  expect(result.succeeded() && result.stats.frames == 0, "public RenderResult defaults");

  const strok::ColorImageView image;
  expect(image.data == nullptr && image.pixel_format == strok::ColorPixelFormat::Rgb24, "public ColorImageView defaults");

  const strok::DepthImageView depth;
  expect(depth.data == nullptr && depth.interpretation == strok::DepthInterpretation::CameraLinear, "public DepthImageView defaults");

  const strok::Frame frame{.w = 1, .h = 1, .rgb = {0, 0, 0}};
  const std::optional<strok::ColorImageView> frame_image = strok::colorImageViewFromFrame(frame);
  expect(frame_image.has_value() && frame_image->data == frame.rgb.data() && frame_image->row_stride_bytes == 3, "public Frame RGB24 adapter");
  strok::CellBuffer rendered;
  const strok::RenderResult render_result = strok::renderFrame(frame, U" @", strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{.cols = 1, .rows = 1}, &rendered);
  expect(render_result.succeeded() && rendered.at(0, 0).glyph == U' ', "public render function");

  const strok::Renderer::CreateResult created = strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{.cols = 1, .rows = 1});
  expect(created.succeeded(), "public Renderer construction");
}
