#pragma once

#include "cell_buffer.hpp"
#include "color_image_view.hpp"
#include "frame.hpp"
#include "renderer_config.hpp"
#include "render_grid.hpp"
#include "render_input.hpp"
#include "render_result.hpp"

#include <string_view>

namespace strok {

// This pre-1.0 C++ API is provisional and may change before a stable release.
RenderResult renderFrame(const Frame& frame, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, CellBuffer* output);
RenderResult renderFrame(const ColorImageView& image, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, CellBuffer* output);
RenderResult renderFrame(const RenderInput& input, std::u32string_view ramp, const RendererConfig& config, RenderGrid available_grid, CellBuffer* output);

}  // namespace strok
