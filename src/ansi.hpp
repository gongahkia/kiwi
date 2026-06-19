#pragma once

#include "luminance.hpp"

#include <string>

namespace contourtty {

void appendSgrFg(std::string& out, Rgb color);
void appendSgrBg(std::string& out, Rgb color);
void appendSgrReset(std::string& out);
void appendCursorMove(std::string& out, int row, int col);
void appendUtf8(std::string& out, char32_t codepoint);

}  // namespace contourtty
