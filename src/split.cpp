#include "split.hpp"

#include <algorithm>
#include <stdexcept>

namespace contourtty {
namespace {

std::optional<SplitSpec> parsePair(std::string_view value, char separator) {
  const std::size_t first = value.find(separator);
  if (first == std::string_view::npos || first == 0 || first + 1 >= value.size()) {
    return std::nullopt;
  }
  if (value.find(separator, first + 1) != std::string_view::npos) {
    return std::nullopt;
  }
  return SplitSpec{
    .left = std::string(value.substr(0, first)),
    .right = std::string(value.substr(first + 1)),
  };
}

int centeredOffset(int region_cols, int content_cols) {
  return std::max(0, (region_cols - content_cols) / 2);
}

}  // namespace

std::optional<SplitSpec> parseSplitSpec(std::string_view value) {
  const std::optional<SplitSpec> parsed = parsePair(value, ':');
  if (!parsed.has_value() || !splitBranchNameValid(parsed->left) || !splitBranchNameValid(parsed->right)) {
    return std::nullopt;
  }
  return parsed;
}

std::optional<SplitSpec> parseSplitGraphSpec(std::string_view value) {
  return parsePair(value, ',');
}

bool splitBranchNameValid(std::string_view value) noexcept {
  return value == "auto" ||
         value == "luminance" ||
         value == "structure" ||
         value == "halfblock" ||
         value == "blocks" ||
         value == "octant" ||
         value == "sextant" ||
         value == "braille";
}

void applySplitBranch(std::string_view value, CliOptions* options) {
  if (options == nullptr) {
    throw std::invalid_argument("options must not be null");
  }
  if (!splitBranchNameValid(value)) {
    throw std::invalid_argument("invalid split branch: " + std::string(value));
  }
  options->pipeline = std::string(value);
  options->mode = std::string(value);
  options->graph_passes.clear();
}

int clampSplitSeam(int seam_col, int total_cols) {
  if (total_cols < 3) {
    return 0;
  }
  return std::clamp(seam_col, 1, total_cols - 2);
}

int defaultSplitSeam(int total_cols) {
  return clampSplitSeam(total_cols / 2, total_cols);
}

SplitLayout splitLayout(int total_cols, int seam_col) {
  if (total_cols < 3) {
    throw std::invalid_argument("split layout needs at least 3 columns");
  }
  const int clamped = clampSplitSeam(seam_col, total_cols);
  return SplitLayout{
    .left_cols = clamped,
    .seam_col = clamped,
    .right_cols = total_cols - clamped - 1,
  };
}

void composeSplitCells(const CellBuffer& left, const CellBuffer& right, const SplitLayout& layout, CellBuffer* output) {
  if (output == nullptr) {
    throw std::invalid_argument("output must not be null");
  }
  if (layout.left_cols <= 0 || layout.right_cols <= 0) {
    throw std::invalid_argument("split layout halves must be positive");
  }
  const int rows = std::max(left.rows(), right.rows());
  const int total_cols = layout.left_cols + 1 + layout.right_cols;
  output->resize(total_cols, rows);
  std::fill(output->cells().begin(), output->cells().end(), Cell{});

  const int left_x = centeredOffset(layout.left_cols, left.cols());
  const int left_y = std::max(0, (rows - left.rows()) / 2);
  for (int row = 0; row < left.rows(); ++row) {
    for (int col = 0; col < left.cols() && left_x + col < layout.left_cols; ++col) {
      output->at(left_x + col, left_y + row) = left.at(col, row);
    }
  }

  const Cell seam {
    .glyph = U'┃',
    .fg = Rgb{.r = 180, .g = 180, .b = 180},
    .bg = Rgb{},
  };
  for (int row = 0; row < rows; ++row) {
    output->at(layout.seam_col, row) = seam;
  }

  const int right_x = layout.seam_col + 1 + centeredOffset(layout.right_cols, right.cols());
  const int right_y = std::max(0, (rows - right.rows()) / 2);
  for (int row = 0; row < right.rows(); ++row) {
    for (int col = 0; col < right.cols() && right_x + col < total_cols; ++col) {
      output->at(right_x + col, right_y + row) = right.at(col, row);
    }
  }
}

}  // namespace contourtty
