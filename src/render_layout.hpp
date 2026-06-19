#pragma once

#include "cli.hpp"
#include "frame.hpp"
#include "terminal.hpp"

namespace contourtty {

struct RenderSize {
  int cols = 0;
  int rows = 0;
};

struct RenderOrigin {
  int row = 1;
  int col = 1;
};

RenderSize fitRenderSize(const Frame& frame, const CliOptions& options, TerminalSize terminal);
RenderOrigin centeredOrigin(RenderSize size, TerminalSize terminal);

}  // namespace contourtty
