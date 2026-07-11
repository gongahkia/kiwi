#include "color_mode.hpp"

#include <algorithm>
#include <cctype>
#include <stdexcept>
#include <string>
#include <string_view>

namespace strok {
namespace {

std::string lower(std::string_view value) {
  std::string out(value);
  std::transform(out.begin(), out.end(), out.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return out;
}

bool hasValue(const char* value) noexcept {
  return value != nullptr && value[0] != '\0';
}

}  // namespace

ColorMode detectColorMode(const char* term, const char* colorterm, const char* no_color) {
  if (hasValue(no_color)) {
    return ColorMode::Mono;
  }
  const std::string colorterm_value = hasValue(colorterm) ? lower(colorterm) : std::string{};
  if (colorterm_value == "truecolor" || colorterm_value == "24bit") {
    return ColorMode::Truecolor;
  }
  const std::string term_value = hasValue(term) ? lower(term) : std::string{};
  if (term_value.find("256") != std::string::npos) {
    return ColorMode::Color256;
  }
  return ColorMode::Color16;
}

ColorMode resolveColorMode(std::string_view requested, const char* term, const char* colorterm, const char* no_color) {
  if (hasValue(no_color)) {
    return ColorMode::Mono;
  }
  if (requested == "auto") {
    return detectColorMode(term, colorterm, no_color);
  }
  if (requested == "truecolor") {
    return ColorMode::Truecolor;
  }
  if (requested == "256") {
    return ColorMode::Color256;
  }
  if (requested == "16") {
    return ColorMode::Color16;
  }
  if (requested == "mono") {
    return ColorMode::Mono;
  }
  throw std::invalid_argument("unknown color mode");
}

bool emitsTruecolor(ColorMode mode) noexcept {
  return mode == ColorMode::Truecolor;
}

std::string_view colorModeName(ColorMode mode) noexcept {
  switch (mode) {
    case ColorMode::Truecolor:
      return "truecolor";
    case ColorMode::Color256:
      return "256";
    case ColorMode::Color16:
      return "16";
    case ColorMode::Mono:
      return "mono";
  }
  return "mono";
}

}  // namespace strok
