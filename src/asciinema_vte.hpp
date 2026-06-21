#pragma once

#include "cell_buffer.hpp"

#include <string_view>

namespace contourtty {

class AsciinemaVteScreen {
 public:
  AsciinemaVteScreen(int cols, int rows);

  void applyOutput(std::string_view bytes);

  const CellBuffer& cells() const noexcept;
  int cursorCol() const noexcept;
  int cursorRow() const noexcept;

 private:
  void putGlyph(char32_t glyph);
  void lineFeed();
  void scrollUp(int lines);
  void clearCell(int col, int row);
  void clearDisplay(int mode);
  void clearLine(int mode);
  void applyCsi(std::string_view sequence);
  void applySgr(std::string_view params);

  CellBuffer cells_;
  int cursor_col_ = 0;
  int cursor_row_ = 0;
  Rgb fg_ {};
  Rgb bg_ {};
};

}  // namespace contourtty
