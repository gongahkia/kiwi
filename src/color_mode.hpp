#pragma once

#include "../include/strok/raster.hpp"

#include <string_view>

namespace strok {

ColorMode detectColorMode(const char* term, const char* colorterm, const char* no_color);
ColorMode resolveColorMode(std::string_view requested, const char* term, const char* colorterm, const char* no_color);
bool emitsTruecolor(ColorMode mode) noexcept;
std::string_view colorModeName(ColorMode mode) noexcept;

}  // namespace strok
