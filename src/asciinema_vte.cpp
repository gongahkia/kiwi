#include "asciinema_vte.hpp"

#include "color_quantization.hpp"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <vector>

namespace strok {
namespace {

bool isCsiFinal(unsigned char ch) noexcept {
  return ch >= 0x40U && ch <= 0x7eU;
}

std::vector<int> parseParams(std::string_view params) {
  std::vector<int> values;
  int value = 0;
  bool has_value = false;
  for (char ch : params) {
    if (ch >= '0' && ch <= '9') {
      value = value * 10 + (ch - '0');
      has_value = true;
      continue;
    }
    if (ch == ';' || ch == ':' || ch == '?') {
      values.push_back(has_value ? value : 0);
      value = 0;
      has_value = false;
    }
  }
  values.push_back(has_value ? value : 0);
  return values;
}

int paramOrDefault(const std::vector<int>& params, std::size_t index, int fallback) noexcept {
  if (index >= params.size() || params[index] == 0) {
    return fallback;
  }
  return params[index];
}

int clampIndex(int value, int limit) noexcept {
  return std::clamp(value, 0, std::max(0, limit - 1));
}

bool decodeUtf8(std::string_view bytes, std::size_t* index, char32_t* glyph) noexcept {
  const auto lead = static_cast<unsigned char>(bytes[*index]);
  if (lead < 0x80U) {
    *glyph = lead;
    ++(*index);
    return true;
  }
  int extra = 0;
  char32_t value = 0;
  if ((lead & 0xe0U) == 0xc0U) {
    extra = 1;
    value = lead & 0x1fU;
  } else if ((lead & 0xf0U) == 0xe0U) {
    extra = 2;
    value = lead & 0x0fU;
  } else if ((lead & 0xf8U) == 0xf0U) {
    extra = 3;
    value = lead & 0x07U;
  } else {
    ++(*index);
    *glyph = U'?';
    return false;
  }
  if (*index + static_cast<std::size_t>(extra) >= bytes.size()) {
    *index = bytes.size();
    *glyph = U'?';
    return false;
  }
  for (int i = 1; i <= extra; ++i) {
    const auto byte = static_cast<unsigned char>(bytes[*index + static_cast<std::size_t>(i)]);
    if ((byte & 0xc0U) != 0x80U) {
      ++(*index);
      *glyph = U'?';
      return false;
    }
    value = (value << 6U) | (byte & 0x3fU);
  }
  *index += static_cast<std::size_t>(extra + 1);
  *glyph = value;
  return true;
}

}  // namespace

AsciinemaVteScreen::AsciinemaVteScreen(int cols, int rows) : cells_(cols, rows) {}

void AsciinemaVteScreen::applyOutput(std::string_view bytes) {
  for (std::size_t index = 0; index < bytes.size();) {
    const unsigned char ch = static_cast<unsigned char>(bytes[index]);
    if (ch == 0x1bU) {
      if (index + 1 < bytes.size() && bytes[index + 1] == '[') {
        std::size_t end = index + 2;
        while (end < bytes.size() && !isCsiFinal(static_cast<unsigned char>(bytes[end]))) {
          ++end;
        }
        if (end < bytes.size()) {
          applyCsi(bytes.substr(index + 2, end - index - 1));
          index = end + 1;
          continue;
        }
      }
      ++index;
      continue;
    }
    if (ch == '\n') {
      lineFeed();
      ++index;
      continue;
    }
    if (ch == '\r') {
      cursor_col_ = 0;
      ++index;
      continue;
    }
    if (ch == '\b') {
      cursor_col_ = std::max(0, cursor_col_ - 1);
      ++index;
      continue;
    }
    if (ch < 0x20U || ch == 0x7fU) {
      ++index;
      continue;
    }
    char32_t glyph = U'?';
    (void)decodeUtf8(bytes, &index, &glyph);
    putGlyph(glyph);
  }
}

const CellBuffer& AsciinemaVteScreen::cells() const noexcept {
  return cells_;
}

int AsciinemaVteScreen::cursorCol() const noexcept {
  return cursor_col_;
}

int AsciinemaVteScreen::cursorRow() const noexcept {
  return cursor_row_;
}

void AsciinemaVteScreen::putGlyph(char32_t glyph) {
  if (cursor_col_ >= cells_.cols()) {
    cursor_col_ = 0;
    lineFeed();
  }
  Cell& cell = cells_.at(cursor_col_, cursor_row_);
  cell.glyph = glyph;
  cell.fg = fg_;
  cell.bg = bg_;
  ++cursor_col_;
}

void AsciinemaVteScreen::lineFeed() {
  if (cursor_col_ >= cells_.cols()) {
    cursor_col_ = 0;
  }
  ++cursor_row_;
  if (cursor_row_ >= cells_.rows()) {
    scrollUp(1);
    cursor_row_ = cells_.rows() - 1;
  }
}

void AsciinemaVteScreen::scrollUp(int lines) {
  lines = std::clamp(lines, 0, cells_.rows());
  if (lines == 0) {
    return;
  }
  const int cols = cells_.cols();
  const int rows = cells_.rows();
  auto& storage = cells_.cells();
  for (int row = 0; row < rows - lines; ++row) {
    for (int col = 0; col < cols; ++col) {
      storage[static_cast<std::size_t>(row * cols + col)] = storage[static_cast<std::size_t>((row + lines) * cols + col)];
    }
  }
  for (int row = rows - lines; row < rows; ++row) {
    for (int col = 0; col < cols; ++col) {
      clearCell(col, row);
    }
  }
}

void AsciinemaVteScreen::clearCell(int col, int row) {
  cells_.at(col, row) = Cell{.glyph = U' ', .fg = fg_, .bg = bg_};
}

void AsciinemaVteScreen::clearDisplay(int mode) {
  if (mode == 2 || mode == 3) {
    for (int row = 0; row < cells_.rows(); ++row) {
      for (int col = 0; col < cells_.cols(); ++col) {
        clearCell(col, row);
      }
    }
    cursor_col_ = 0;
    cursor_row_ = 0;
    return;
  }
  if (mode == 1) {
    for (int row = 0; row <= cursor_row_; ++row) {
      const int last_col = row == cursor_row_ ? cursor_col_ : cells_.cols() - 1;
      for (int col = 0; col <= last_col; ++col) {
        clearCell(col, row);
      }
    }
    return;
  }
  for (int row = cursor_row_; row < cells_.rows(); ++row) {
    const int first_col = row == cursor_row_ ? cursor_col_ : 0;
    for (int col = first_col; col < cells_.cols(); ++col) {
      clearCell(col, row);
    }
  }
}

void AsciinemaVteScreen::clearLine(int mode) {
  if (mode == 2) {
    for (int col = 0; col < cells_.cols(); ++col) {
      clearCell(col, cursor_row_);
    }
    return;
  }
  const int first_col = mode == 1 ? 0 : cursor_col_;
  const int last_col = mode == 1 ? cursor_col_ : cells_.cols() - 1;
  for (int col = first_col; col <= last_col; ++col) {
    clearCell(col, cursor_row_);
  }
}

void AsciinemaVteScreen::applyCsi(std::string_view sequence) {
  if (sequence.empty()) {
    return;
  }
  const char command = sequence.back();
  const std::string_view params_text = sequence.substr(0, sequence.size() - 1);
  const std::vector<int> params = parseParams(params_text);
  switch (command) {
    case 'A':
      cursor_row_ = clampIndex(cursor_row_ - paramOrDefault(params, 0, 1), cells_.rows());
      break;
    case 'B':
      cursor_row_ = clampIndex(cursor_row_ + paramOrDefault(params, 0, 1), cells_.rows());
      break;
    case 'C':
      cursor_col_ = clampIndex(cursor_col_ + paramOrDefault(params, 0, 1), cells_.cols());
      break;
    case 'D':
      cursor_col_ = clampIndex(cursor_col_ - paramOrDefault(params, 0, 1), cells_.cols());
      break;
    case 'H':
    case 'f':
      cursor_row_ = clampIndex(paramOrDefault(params, 0, 1) - 1, cells_.rows());
      cursor_col_ = clampIndex(paramOrDefault(params, 1, 1) - 1, cells_.cols());
      break;
    case 'J':
      clearDisplay(paramOrDefault(params, 0, 0));
      break;
    case 'K':
      clearLine(paramOrDefault(params, 0, 0));
      break;
    case 'S':
      scrollUp(paramOrDefault(params, 0, 1));
      break;
    case 'm':
      applySgr(params_text);
      break;
    default:
      break;
  }
}

void AsciinemaVteScreen::applySgr(std::string_view params_text) {
  const std::vector<int> params = parseParams(params_text);
  for (std::size_t index = 0; index < params.size(); ++index) {
    const int param = params[index];
    if (param == 0) {
      fg_ = Rgb{};
      bg_ = Rgb{};
    } else if (param >= 30 && param <= 37) {
      fg_ = ansi16Color(static_cast<uint8_t>(param - 30));
    } else if (param >= 40 && param <= 47) {
      bg_ = ansi16Color(static_cast<uint8_t>(param - 40));
    } else if (param >= 90 && param <= 97) {
      fg_ = ansi16Color(static_cast<uint8_t>(param - 90 + 8));
    } else if (param >= 100 && param <= 107) {
      bg_ = ansi16Color(static_cast<uint8_t>(param - 100 + 8));
    } else if ((param == 38 || param == 48) && index + 2 < params.size() && params[index + 1] == 5) {
      const Rgb color = xterm256Color(static_cast<uint8_t>(std::clamp(params[index + 2], 0, 255)));
      if (param == 38) {
        fg_ = color;
      } else {
        bg_ = color;
      }
      index += 2;
    } else if ((param == 38 || param == 48) && index + 4 < params.size() && params[index + 1] == 2) {
      const Rgb color{
        .r = static_cast<uint8_t>(std::clamp(params[index + 2], 0, 255)),
        .g = static_cast<uint8_t>(std::clamp(params[index + 3], 0, 255)),
        .b = static_cast<uint8_t>(std::clamp(params[index + 4], 0, 255)),
      };
      if (param == 38) {
        fg_ = color;
      } else {
        bg_ = color;
      }
      index += 4;
    } else if (param == 39) {
      fg_ = Rgb{};
    } else if (param == 49) {
      bg_ = Rgb{};
    }
  }
}

}  // namespace strok
