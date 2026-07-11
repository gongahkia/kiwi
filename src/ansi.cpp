#include "ansi.hpp"

#include <stdexcept>
#include <string>

namespace strok {

void appendSgrFg(std::string& out, Rgb color) {
  out += "\x1b[38;2;";
  out += std::to_string(color.r);
  out += ';';
  out += std::to_string(color.g);
  out += ';';
  out += std::to_string(color.b);
  out += 'm';
}

void appendSgrBg(std::string& out, Rgb color) {
  out += "\x1b[48;2;";
  out += std::to_string(color.r);
  out += ';';
  out += std::to_string(color.g);
  out += ';';
  out += std::to_string(color.b);
  out += 'm';
}

void appendSgrFg256(std::string& out, uint8_t color_index) {
  out += "\x1b[38;5;";
  out += std::to_string(color_index);
  out += 'm';
}

void appendSgrBg256(std::string& out, uint8_t color_index) {
  out += "\x1b[48;5;";
  out += std::to_string(color_index);
  out += 'm';
}

void appendSgrFg16(std::string& out, uint8_t color_index) {
  out += "\x1b[";
  out += std::to_string(color_index < 8 ? 30 + color_index : 90 + color_index - 8);
  out += 'm';
}

void appendSgrBg16(std::string& out, uint8_t color_index) {
  out += "\x1b[";
  out += std::to_string(color_index < 8 ? 40 + color_index : 100 + color_index - 8);
  out += 'm';
}

void appendSgrReset(std::string& out) {
  out += "\x1b[0m";
}

void appendCursorMove(std::string& out, int row, int col) {
  if (row <= 0 || col <= 0) {
    throw std::invalid_argument("cursor position is 1-based");
  }
  out += "\x1b[";
  out += std::to_string(row);
  out += ';';
  out += std::to_string(col);
  out += 'H';
}

void appendUtf8(std::string& out, char32_t codepoint) {
  if (codepoint <= 0x7f) {
    out.push_back(static_cast<char>(codepoint));
  } else if (codepoint <= 0x7ff) {
    out.push_back(static_cast<char>(0xc0U | ((codepoint >> 6U) & 0x1fU)));
    out.push_back(static_cast<char>(0x80U | (codepoint & 0x3fU)));
  } else if (codepoint <= 0xffff) {
    if (codepoint >= 0xd800U && codepoint <= 0xdfffU) {
      throw std::invalid_argument("invalid unicode surrogate");
    }
    out.push_back(static_cast<char>(0xe0U | ((codepoint >> 12U) & 0x0fU)));
    out.push_back(static_cast<char>(0x80U | ((codepoint >> 6U) & 0x3fU)));
    out.push_back(static_cast<char>(0x80U | (codepoint & 0x3fU)));
  } else if (codepoint <= 0x10ffffU) {
    out.push_back(static_cast<char>(0xf0U | ((codepoint >> 18U) & 0x07U)));
    out.push_back(static_cast<char>(0x80U | ((codepoint >> 12U) & 0x3fU)));
    out.push_back(static_cast<char>(0x80U | ((codepoint >> 6U) & 0x3fU)));
    out.push_back(static_cast<char>(0x80U | (codepoint & 0x3fU)));
  } else {
    throw std::invalid_argument("invalid unicode codepoint");
  }
}

}  // namespace strok
