#include "../include/strok/render.hpp"
#include "../include/strok/renderer.hpp"

#include "renderer.hpp"

#include <exception>
#include <memory>
#include <utility>

namespace strok {

struct Renderer::State {
  RendererConfig config;
  RenderGrid grid;
  RenderTemporalState temporal_state;
};

RenderResult renderFrame(const Frame& frame, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, CellBuffer* output) {
  return renderFrame(frame, ramp, config, available_grid, nullptr, output, nullptr, nullptr);
}

Renderer::Renderer(RendererConfig config, RenderGrid grid)
    : state_(std::make_unique<State>(State{
        .config = std::move(config),
        .grid = grid,
      })) {}

Renderer::~Renderer() = default;

Renderer::CreateResult Renderer::create(RendererConfig config, RenderGrid grid) {
  const RenderResult validation = validateRendererConfiguration(config, grid);
  if (!validation.succeeded()) {
    return CreateResult{.result = validation};
  }
  try {
    return CreateResult{
      .renderer = std::unique_ptr<Renderer>(new Renderer(std::move(config), grid)),
      .result = RenderResult{},
    };
  } catch (const std::exception& error) {
    return CreateResult{.result = RenderResult{
                          .status = RenderStatus::InternalError,
                          .message = error.what(),
                        }};
  } catch (...) {
    return CreateResult{.result = RenderResult{
                          .status = RenderStatus::InternalError,
                          .message = "unexpected renderer initialization failure",
                        }};
  }
}

RenderResult Renderer::render(const Frame& frame, std::u32string_view ramp, CellBuffer* output) {
  return renderFrame(frame, ramp, state_->config, state_->grid, nullptr, output, &state_->temporal_state, nullptr);
}

void Renderer::reset() {
  state_->temporal_state.reset();
}

}  // namespace strok
