#pragma once

#include "cell_buffer.hpp"
#include "cli.hpp"

#include <optional>
#include <string>
#include <string_view>

namespace strok {

struct SplitSpec {
  std::string left;
  std::string right;
};

struct SplitLayout {
  int left_cols = 0;
  int seam_col = 0;
  int right_cols = 0;
};

std::optional<SplitSpec> parseSplitSpec(std::string_view value);
std::optional<SplitSpec> parseSplitGraphSpec(std::string_view value);
bool splitBranchNameValid(std::string_view value) noexcept;
void applySplitBranch(std::string_view value, CliOptions* options);
int clampSplitSeam(int seam_col, int total_cols);
int defaultSplitSeam(int total_cols);
SplitLayout splitLayout(int total_cols, int seam_col);
void composeSplitCells(const CellBuffer& left, const CellBuffer& right, const SplitLayout& layout, CellBuffer* output);

}  // namespace strok
