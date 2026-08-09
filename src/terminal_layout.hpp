#pragma once

#include "terminal.hpp"

namespace strok {

struct TerminalRenderOrigin {
  int row = 1;
  int col = 1;
};

TerminalRenderOrigin centeredTerminalOrigin(int cols, int rows, TerminalSize terminal);

}  // namespace strok
