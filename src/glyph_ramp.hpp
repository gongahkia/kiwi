#pragma once

#include <string>
#include <string_view>

namespace contourtty {

constexpr std::u32string_view kDefaultGlyphRamp = U" .:-=+*#%@";

std::u32string decodeCharset(std::string_view charset);
std::u32string resolveCharsetRamp(std::string_view charset);
bool isValidCharset(std::string_view charset) noexcept;
bool isBrailleCharset(std::string_view charset) noexcept;
char32_t glyphForLuminance(double luminance, std::u32string_view ramp = kDefaultGlyphRamp);

}  // namespace contourtty
