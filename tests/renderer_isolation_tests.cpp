#include <strok/renderer.hpp>

#include <cstdlib>
#include <cstdint>
#include <iostream>
#include <utility>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

strok::Frame solidFrame(uint8_t value) {
  return strok::Frame{
    .w = 4,
    .h = 4,
    .rgb = {
      value, value, value, value, value, value, value, value, value, value, value, value,
      value, value, value, value, value, value, value, value, value, value, value, value,
      value, value, value, value, value, value, value, value, value, value, value, value,
      value, value, value, value, value, value, value, value, value, value, value, value,
    },
  };
}

strok::Frame checkerboardFrame(bool inverted) {
  strok::Frame frame{
    .w = 4,
    .h = 4,
    .rgb = {},
  };
  frame.rgb.reserve(4U * 4U * 3U);
  for (int row = 0; row < frame.h; ++row) {
    for (int col = 0; col < frame.w; ++col) {
      const bool white = ((row + col) % 2 == 0) != inverted;
      const uint8_t value = white ? 255U : 0U;
      frame.rgb.insert(frame.rgb.end(), {value, value, value});
    }
  }
  return frame;
}

strok::Renderer::CreateResult createRenderer(strok::RendererConfig config) {
  return strok::Renderer::create(std::move(config), strok::RenderGrid{.cols = 2, .rows = 2});
}

}  // namespace

int main() {
  strok::RendererConfig standard_config;
  standard_config.cell_aspect = 1.0;
  strok::Renderer::CreateResult standard = createRenderer(std::move(standard_config));

  strok::RendererConfig binary_config;
  binary_config.cell_aspect = 1.0;
  binary_config.charset = "binary";
  strok::Renderer::CreateResult binary = createRenderer(std::move(binary_config));

  expect(standard.succeeded() && binary.succeeded(), "independent renderer construction");
  expect(standard.renderer->render(solidFrame(255)).succeeded(), "standard renderer render");
  expect(binary.renderer->render(solidFrame(255)).succeeded(), "binary renderer render");
  expect(standard.renderer->cells().at(0, 0).glyph == U'@', "standard renderer glyph state");
  expect(binary.renderer->cells().at(0, 0).glyph == U'1', "binary renderer glyph state");
  expect(standard.renderer->cells().at(0, 0).glyph != binary.renderer->cells().at(0, 0).glyph, "renderer glyph state isolation");

  strok::RendererConfig flow_config;
  flow_config.cell_aspect = 1.0;
  flow_config.style = "flow";
  flow_config.glyph_stickiness = 0.0;
  strok::Renderer::CreateResult first_stream = createRenderer(flow_config);
  strok::Renderer::CreateResult second_stream = createRenderer(std::move(flow_config));
  expect(first_stream.succeeded() && second_stream.succeeded(), "temporal renderer construction");

  const strok::RenderResult first_initial = first_stream.renderer->render(checkerboardFrame(false));
  const strok::RenderResult second_initial = second_stream.renderer->render(checkerboardFrame(true));
  expect(first_initial.succeeded() && first_initial.stats.optical_flow_blocks == 0, "first stream starts without history");
  expect(second_initial.succeeded() && second_initial.stats.optical_flow_blocks == 0, "second stream starts without first stream history");

  const strok::RenderResult first_followup = first_stream.renderer->render(checkerboardFrame(true));
  const strok::RenderResult second_followup = second_stream.renderer->render(checkerboardFrame(false));
  expect(first_followup.succeeded() && first_followup.stats.optical_flow_blocks == 1, "first stream uses only its history");
  expect(second_followup.succeeded() && second_followup.stats.optical_flow_blocks == 1, "second stream uses only its history");
}
