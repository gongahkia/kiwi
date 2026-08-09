#pragma once

#include "../include/strok/renderer_config.hpp"

#include "frame.hpp"
#include "terminal.hpp"

namespace strok {

struct RenderSize {
  int cols = 0;
  int rows = 0;
};

struct RenderOrigin {
  int row = 1;
  int col = 1;
};

RenderSize fitRenderSize(const Frame& frame, const RendererConfig& config, TerminalSize terminal);
RenderOrigin centeredOrigin(RenderSize size, TerminalSize terminal);

}  // namespace strok
