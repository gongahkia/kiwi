#pragma once

#include "luminance.hpp"

#include <string>

namespace strok {

void appendSgrFg(std::string& out, Rgb color);
void appendSgrBg(std::string& out, Rgb color);
void appendSgrFg256(std::string& out, uint8_t color_index);
void appendSgrBg256(std::string& out, uint8_t color_index);
void appendSgrFg16(std::string& out, uint8_t color_index);
void appendSgrBg16(std::string& out, uint8_t color_index);
void appendSgrReset(std::string& out);
void appendCursorMove(std::string& out, int row, int col);
void appendUtf8(std::string& out, char32_t codepoint);

}  // namespace strok
