#include "terminal_layout.hpp"

#include <algorithm>

namespace strok {

TerminalRenderOrigin centeredTerminalOrigin(int cols, int rows, TerminalSize terminal) {
  return TerminalRenderOrigin{
    .row = std::max(1, ((terminal.rows - rows) / 2) + 1),
    .col = std::max(1, ((terminal.cols - cols) / 2) + 1),
  };
}

}  // namespace strok
