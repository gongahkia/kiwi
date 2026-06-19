#include "glyph_ramp.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  expect(contourtty::glyphForLuminance(0.0) == U' ', "black maps to first ramp glyph");
  expect(contourtty::glyphForLuminance(1.0) == U'@', "white maps to last ramp glyph");
  expect(contourtty::glyphForLuminance(0.5) == U'+', "mid luminance maps by rounded index");
  expect(contourtty::glyphForLuminance(-1.0) == U' ', "low luminance clamps");
  expect(contourtty::glyphForLuminance(2.0) == U'@', "high luminance clamps");
  expect(contourtty::glyphForLuminance(0.75, U"ab") == U'b', "custom ramp maps");

  const auto ascii = contourtty::decodeCharset(" .#");
  expect(ascii.size() == 3 && ascii[0] == U' ' && ascii[2] == U'#', "ascii charset decodes");

  const auto unicode = contourtty::decodeCharset(" ░█");
  expect(unicode.size() == 3 && unicode[1] == U'░' && unicode[2] == U'█', "unicode charset decodes");
  expect(contourtty::resolveCharsetRamp("blocks") == U" ░▒▓█", "blocks preset resolves");
  expect(contourtty::resolveCharsetRamp("binary") == U" 01", "binary preset resolves");
  expect(contourtty::resolveCharsetRamp("detailed").size() > contourtty::kDefaultGlyphRamp.size(), "detailed preset resolves");
  expect(contourtty::isBrailleCharset("braille"), "braille preset detected");
  expect(contourtty::isValidCharset("abc"), "valid charset accepted");
  expect(contourtty::isValidCharset("braille"), "braille charset accepted");
  expect(!contourtty::isValidCharset(""), "empty charset rejected");

  std::string invalid;
  invalid.push_back(static_cast<char>(0xc0));
  invalid.push_back(static_cast<char>(0x80));
  expect(!contourtty::isValidCharset(invalid), "invalid UTF-8 rejected");
}
