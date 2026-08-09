#include <strok/render.hpp>
#include <strok/renderer.hpp>

#include <array>
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
  expect(color_cells == created.renderer->cells(), "depth input preserves current RGB reconstruction");
  expect(created.renderer->render(strok::RenderInput{.color = color_view, .normals = normal_view}).succeeded(), "color and normal RenderInput");
  expect(color_cells == created.renderer->cells(), "normal input preserves current RGB reconstruction");
  expect(created.renderer->render(strok::RenderInput{.color = color_view, .depth = depth_view, .normals = normal_view}).succeeded(), "full RenderInput");
  expect(color_cells == created.renderer->cells(), "combined input preserves current RGB reconstruction");

  const strok::Frame frame{.w = 1, .h = 1, .rgb = {255, 0, 0}};
  expect(created.renderer->render(frame).succeeded() && color_cells == created.renderer->cells(), "Frame adapts to color-only RenderInput");

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

  const std::array<uint8_t, 6> shade_color = {255, 255, 255, 255, 255, 255};
  const std::array<double, 2> shade_depth = {0.0, 1.0};
  const std::array<double, 6> shade_normals = {0.0, 0.0, 1.0, 0.0, 0.0, 1.0};
  const strok::ColorImageView shade_color_view{
    .data = shade_color.data(),
    .width = 2,
    .height = 1,
    .row_stride_bytes = 6,
    .pixel_format = strok::ColorPixelFormat::Rgb24,
  };
  const strok::DepthImageView shade_depth_view{
    .data = shade_depth.data(),
    .width = 2,
    .height = 1,
    .row_stride_bytes = 2U * sizeof(double),
  };
  const strok::NormalImageView shade_normal_view{
    .data = shade_normals.data(),
    .width = 2,
    .height = 1,
    .row_stride_bytes = 6U * sizeof(double),
  };
  strok::Renderer::CreateResult cell_shade = strok::Renderer::create(
      strok::RendererConfig{.cell_aspect = 1.0, .style = "cell-shade"},
      strok::RenderGrid{.cols = 2, .rows = 1});
  expect(cell_shade.succeeded(), "cell-shade renderer construction");
  expect(cell_shade.renderer->render(strok::RenderInput{
      .color = shade_color_view,
      .depth = shade_depth_view,
      .normals = shade_normal_view,
    }).succeeded(),
         "generic cell-shade RenderInput");
  const strok::CellBuffer& shaded_cells = cell_shade.renderer->cells();
  expect(shaded_cells.at(0, 0).fg.r > shaded_cells.at(1, 0).fg.r, "generic depth input darkens far cell");
  expect(shaded_cells.at(0, 0).glyph != shaded_cells.at(1, 0).glyph, "generic depth input shifts ramp glyph");

  const std::array<double, 2> flat_depth = {0.0, 0.0};
  const std::array<double, 6> orientation_normals = {1.0, 0.0, 0.0, 0.0, 1.0, 0.0};
  expect(cell_shade.renderer->render(strok::RenderInput{
      .color = shade_color_view,
      .depth = strok::DepthImageView{
          .data = flat_depth.data(),
          .width = 2,
          .height = 1,
          .row_stride_bytes = 2U * sizeof(double),
      },
      .normals = strok::NormalImageView{
          .data = orientation_normals.data(),
          .width = 2,
          .height = 1,
          .row_stride_bytes = 6U * sizeof(double),
      },
    }).succeeded(),
         "generic normal-orient RenderInput");
  expect(cell_shade.renderer->cells().at(0, 0).glyph == U'─', "external x normal selects horizontal glyph");
  expect(cell_shade.renderer->cells().at(1, 0).glyph == U'│', "external y normal selects vertical glyph");

  strok::CellBuffer cell_shade_output(2, 1);
  cell_shade_output.at(0, 0).glyph = U'X';
  const strok::RenderResult missing_auxiliary = cell_shade.renderer->render(strok::RenderInput{.color = shade_color_view}, &cell_shade_output);
  expect(missing_auxiliary.status == strok::RenderStatus::InvalidInput, "cell-shade rejects color-only input");
  expect(cell_shade_output.at(0, 0).glyph == U'X', "missing cell-shade input preserves output");

  expectInvalid(strok::RenderInput{
      .color = color_view,
      .depth = strok::DepthImageView{
          .data = depth.data(),
          .width = 1,
          .height = 1,
          .row_stride_bytes = sizeof(double),
          .pixel_format = static_cast<strok::DepthPixelFormat>(99),
      },
    },
    "unsupported depth format rejected");
  expectInvalid(strok::RenderInput{
      .color = color_view,
      .normals = strok::NormalImageView{
          .data = normals.data(),
          .width = 1,
          .height = 1,
          .row_stride_bytes = 3U * sizeof(double),
          .space = static_cast<strok::NormalSpace>(99),
      },
    },
    "unsupported normal space rejected");
}
