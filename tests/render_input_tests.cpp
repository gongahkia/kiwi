#include <strok/render.hpp>
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

strok::Renderer::CreateResult createRenderer() {
  return strok::Renderer::create(strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{.cols = 1, .rows = 1});
}

}  // namespace

int main() {
  const std::array<uint8_t, 3> color = {255, 0, 0};
  const std::array<double, 1> depth = {1.0};
  const std::array<double, 3> normals = {0.0, 0.0, 1.0};
  const strok::ColorImageView color_view{
    .data = color.data(),
    .width = 1,
    .height = 1,
    .row_stride_bytes = 3,
    .pixel_format = strok::ColorPixelFormat::Rgb24,
  };
  const strok::DepthImageView depth_view{
    .data = depth.data(),
    .width = 1,
    .height = 1,
    .row_stride_bytes = sizeof(double),
  };
  const strok::NormalImageView normal_view{
    .data = normals.data(),
    .width = 1,
    .height = 1,
    .row_stride_bytes = 3U * sizeof(double),
  };

  strok::Renderer::CreateResult created = createRenderer();
  expect(created.succeeded(), "renderer construction");
  expect(created.renderer->render(strok::RenderInput{.color = color_view}).succeeded(), "color-only RenderInput");
  const strok::CellBuffer color_cells = created.renderer->cells();
  strok::CellBuffer free_cells;
  expect(strok::renderFrame(strok::RenderInput{.color = color_view}, U" @", strok::RendererConfig{.cell_aspect = 1.0}, strok::RenderGrid{.cols = 1, .rows = 1}, &free_cells).succeeded(), "free RenderInput render");
  expect(free_cells.cols() == 1 && free_cells.rows() == 1 &&
             free_cells.at(0, 0).fg.r == 255 &&
             free_cells.at(0, 0).fg.g == 0 &&
             free_cells.at(0, 0).fg.b == 0,
         "free RenderInput output");
  expect(created.renderer->render(strok::RenderInput{.color = color_view, .depth = depth_view}).succeeded(), "color and depth RenderInput");
  expect(sameCells(color_cells, created.renderer->cells()), "depth input preserves current RGB reconstruction");
  expect(created.renderer->render(strok::RenderInput{.color = color_view, .normals = normal_view}).succeeded(), "color and normal RenderInput");
  expect(sameCells(color_cells, created.renderer->cells()), "normal input preserves current RGB reconstruction");
  expect(created.renderer->render(strok::RenderInput{.color = color_view, .depth = depth_view, .normals = normal_view}).succeeded(), "full RenderInput");
  expect(sameCells(color_cells, created.renderer->cells()), "combined input preserves current RGB reconstruction");

  const strok::Frame frame{.w = 1, .h = 1, .rgb = {255, 0, 0}};
  expect(created.renderer->render(frame).succeeded() && sameCells(color_cells, created.renderer->cells()), "Frame adapts to color-only RenderInput");

  const std::array<double, 2> mismatched_depth = {1.0, 2.0};
  const strok::DepthImageView wrong_depth{
    .data = mismatched_depth.data(),
    .width = 2,
    .height = 1,
    .row_stride_bytes = 2U * sizeof(double),
  };
  const std::array<double, 6> mismatched_normals = {0.0, 0.0, 1.0, 0.0, 0.0, 1.0};
  const strok::NormalImageView wrong_normals{
    .data = mismatched_normals.data(),
    .width = 2,
    .height = 1,
    .row_stride_bytes = 6U * sizeof(double),
  };
  strok::CellBuffer output(1, 1);
  output.at(0, 0).glyph = U'X';
  const auto expectInvalid = [&](const strok::RenderInput& input, const char* label) {
    const strok::RenderResult result = created.renderer->render(input, &output);
    expect(result.status == strok::RenderStatus::InvalidInput, label);
    expect(output.at(0, 0).glyph == U'X', "invalid RenderInput preserves output");
  };
  expectInvalid(strok::RenderInput{.color = color_view, .depth = wrong_depth}, "depth dimensions must match color");
  expectInvalid(strok::RenderInput{.color = color_view, .normals = wrong_normals}, "normal dimensions must match color");
}
