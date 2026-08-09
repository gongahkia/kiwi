#include "render_layout.hpp"

#include <algorithm>
#include <cmath>

namespace strok {

RenderGrid fitRenderGrid(const Frame& frame, const RendererConfig& config, RenderGrid available_grid) {
  int max_cols = std::max(1, config.width.value_or(available_grid.cols));
  int max_rows = std::max(1, config.height.value_or(available_grid.rows));
  if (config.fit) {
    max_cols = std::min(max_cols, std::max(1, available_grid.cols));
    max_rows = std::min(max_rows, std::max(1, available_grid.rows));
  }
  const double img_aspect = static_cast<double>(frame.w) / static_cast<double>(frame.h);
  const auto rows_for_cols = [&](int cols) {
    return std::max(1, static_cast<int>(std::llround(static_cast<double>(cols) * (1.0 / img_aspect) * config.cell_aspect)));
  };
  const auto cols_for_rows = [&](int rows) {
    return std::max(1, static_cast<int>(std::llround(static_cast<double>(rows) * img_aspect / config.cell_aspect)));
  };

  const int rows = rows_for_cols(max_cols);
  if (rows <= max_rows) {
    return RenderGrid{.cols = max_cols, .rows = rows};
  }
  return RenderGrid{.cols = cols_for_rows(max_rows), .rows = max_rows};
}

}  // namespace strok
