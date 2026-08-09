#pragma once

#include "../include/strok/c_api.h"
#include "../include/strok/render_grid.hpp"
#include "../include/strok/renderer_config.hpp"

#include <optional>
#include <string>

namespace strok {

std::optional<RendererConfig> rendererConfigFromC(const StrokRendererConfig* config, std::string* error = nullptr);
std::optional<RenderGrid> renderGridFromC(const StrokRenderGrid* grid, std::string* error = nullptr);

}  // namespace strok
