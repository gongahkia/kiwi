#include "../include/strok/render.hpp"

#include "renderer.hpp"

namespace strok {

RenderResult renderFrame(const Frame& frame, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, CellBuffer* output) {
  return renderFrame(frame, ramp, config, available_grid, nullptr, output, nullptr, nullptr);
}

}  // namespace strok
