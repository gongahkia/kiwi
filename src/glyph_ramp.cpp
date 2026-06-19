#include "glyph_ramp.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace contourtty {
namespace {

bool isContinuation(unsigned char byte) noexcept {
  return (byte & 0xc0U) == 0x80U;
}

}  // namespace

std::u32string decodeCharset(std::string_view charset) {
  std::u32string decoded;
  for (std::size_t i = 0; i < charset.size();) {
    const auto lead = static_cast<unsigned char>(charset[i]);
    uint32_t codepoint = 0;
    std::size_t needed = 0;
    uint32_t min_codepoint = 0;

    if (lead < 0x80U) {
      codepoint = lead;
      needed = 0;
      min_codepoint = 0;
    } else if ((lead & 0xe0U) == 0xc0U) {
      codepoint = lead & 0x1fU;
      needed = 1;
      min_codepoint = 0x80U;
    } else if ((lead & 0xf0U) == 0xe0U) {
      codepoint = lead & 0x0fU;
      needed = 2;
      min_codepoint = 0x800U;
    } else if ((lead & 0xf8U) == 0xf0U) {
      codepoint = lead & 0x07U;
      needed = 3;
      min_codepoint = 0x10000U;
    } else {
      throw std::invalid_argument("invalid UTF-8 charset");
    }

    if (i + needed >= charset.size()) {
      throw std::invalid_argument("truncated UTF-8 charset");
    }
    for (std::size_t offset = 1; offset <= needed; ++offset) {
      const auto next = static_cast<unsigned char>(charset[i + offset]);
      if (!isContinuation(next)) {
        throw std::invalid_argument("invalid UTF-8 charset");
      }
      codepoint = (codepoint << 6U) | (next & 0x3fU);
    }

    if (codepoint < min_codepoint || (codepoint >= 0xd800U && codepoint <= 0xdfffU) ||
        codepoint > 0x10ffffU) {
      throw std::invalid_argument("invalid UTF-8 charset");
    }
    decoded.push_back(static_cast<char32_t>(codepoint));
    i += needed + 1;
  }

  if (decoded.empty()) {
    throw std::invalid_argument("empty charset");
  }
  return decoded;
}

bool isValidCharset(std::string_view charset) noexcept {
  try {
    (void)decodeCharset(charset);
    return true;
  } catch (...) {
    return false;
  }
}

char32_t glyphForLuminance(double luminance, std::u32string_view ramp) {
  if (ramp.empty()) {
    throw std::invalid_argument("empty glyph ramp");
  }
  if (!std::isfinite(luminance)) {
    luminance = 0.0;
  }
  const double clamped = std::clamp(luminance, 0.0, 1.0);
  const auto index = static_cast<std::size_t>(std::llround(clamped * static_cast<double>(ramp.size() - 1)));
  return ramp[index];
}

}  // namespace contourtty
