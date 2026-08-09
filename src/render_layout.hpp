#pragma once

#include "../include/strok/renderer_config.hpp"
#include "../include/strok/render_grid.hpp"

#include "frame.hpp"

namespace strok {

RenderGrid fitRenderGrid(const Frame& frame, const RendererConfig& config, RenderGrid available_grid);

}  // namespace strok
