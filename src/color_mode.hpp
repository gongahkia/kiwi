#pragma once

#include <string_view>

namespace strok {

enum class ColorMode {
  Truecolor,
  Color256,
  Color16,
  Mono,
};

ColorMode detectColorMode(const char* term, const char* colorterm, const char* no_color);
ColorMode resolveColorMode(std::string_view requested, const char* term, const char* colorterm, const char* no_color);
bool emitsTruecolor(ColorMode mode) noexcept;
std::string_view colorModeName(ColorMode mode) noexcept;

}  // namespace strok
