#include "render_layout.hpp"

#include <algorithm>
#include <cmath>

namespace strok {

RenderSize fitRenderSize(const Frame& frame, const CliOptions& options, TerminalSize terminal) {
  int max_cols = std::max(1, options.width.value_or(terminal.cols));
  int max_rows = std::max(1, options.height.value_or(terminal.rows));
  if (options.fit) {
    max_cols = std::min(max_cols, std::max(1, terminal.cols));
    max_rows = std::min(max_rows, std::max(1, terminal.rows));
  }
  const double img_aspect = static_cast<double>(frame.w) / static_cast<double>(frame.h);
  const auto rows_for_cols = [&](int cols) {
    return std::max(1, static_cast<int>(std::llround(static_cast<double>(cols) * (1.0 / img_aspect) * options.cell_aspect)));
  };
  const auto cols_for_rows = [&](int rows) {
    return std::max(1, static_cast<int>(std::llround(static_cast<double>(rows) * img_aspect / options.cell_aspect)));
  };

  const int rows = rows_for_cols(max_cols);
  if (rows <= max_rows) {
    return RenderSize{.cols = max_cols, .rows = rows};
  }
  return RenderSize{.cols = cols_for_rows(max_rows), .rows = max_rows};
}

RenderOrigin centeredOrigin(RenderSize size, TerminalSize terminal) {
  return RenderOrigin{
    .row = std::max(1, ((terminal.rows - size.rows) / 2) + 1),
    .col = std::max(1, ((terminal.cols - size.cols) / 2) + 1),
  };
}

}  // namespace strok
