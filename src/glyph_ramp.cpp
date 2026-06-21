#include "glyph_ramp.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <stdexcept>
#include <vector>

namespace contourtty {
namespace {

namespace fs = std::filesystem;

bool isContinuation(unsigned char byte) noexcept {
  return (byte & 0xc0U) == 0x80U;
}

std::optional<std::u32string_view> presetRamp(std::string_view charset) {
  if (charset == "standard") {
    return kDefaultGlyphRamp;
  }
  if (charset == "blocks") {
    return U" ░▒▓█";
  }
  if (charset == "detailed") {
    return U" .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$";
  }
  if (charset == "binary") {
    return U" 01";
  }
  return std::nullopt;
}

bool isCharsetName(std::string_view name) {
  if (name.empty()) {
    return false;
  }
  for (const char ch : name) {
    const bool valid = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-' || ch == '_';
    if (!valid) {
      return false;
    }
  }
  return true;
}

std::vector<fs::path> charsetDirs() {
  std::vector<fs::path> dirs;
  if (const char* data_dir = std::getenv("CONTOURTTY_DATA_DIR"); data_dir != nullptr && *data_dir != '\0') {
    dirs.push_back(fs::path(data_dir) / "charsets");
  }
#ifdef CONTOURTTY_SOURCE_DIR
  dirs.push_back(fs::path(CONTOURTTY_SOURCE_DIR) / "share" / "contourtty" / "charsets");
#endif
#ifdef CONTOURTTY_DATA_DIR
  dirs.push_back(fs::path(CONTOURTTY_DATA_DIR) / "charsets");
#endif
  dirs.push_back(fs::path("share") / "contourtty" / "charsets");
  return dirs;
}

std::optional<std::string> jsonStringField(std::string_view json, std::string_view key) {
  const std::string quoted_key = "\"" + std::string(key) + "\"";
  const std::size_t key_pos = json.find(quoted_key);
  if (key_pos == std::string_view::npos) {
    return std::nullopt;
  }
  const std::size_t colon_pos = json.find(':', key_pos + quoted_key.size());
  if (colon_pos == std::string_view::npos) {
    return std::nullopt;
  }
  const std::size_t quote_pos = json.find('"', colon_pos + 1);
  if (quote_pos == std::string_view::npos) {
    return std::nullopt;
  }
  std::string value;
  for (std::size_t i = quote_pos + 1; i < json.size(); ++i) {
    const char ch = json[i];
    if (ch == '"') {
      return value;
    }
    if (ch == '\\') {
      if (++i >= json.size()) {
        return std::nullopt;
      }
      const char escaped = json[i];
      if (escaped == '"' || escaped == '\\' || escaped == '/') {
        value.push_back(escaped);
      } else if (escaped == 'n') {
        value.push_back('\n');
      } else if (escaped == 't') {
        value.push_back('\t');
      } else {
        return std::nullopt;
      }
    } else {
      value.push_back(ch);
    }
  }
  return std::nullopt;
}

std::optional<std::u32string> loadNamedCharset(std::string_view name) {
  if (!isCharsetName(name)) {
    return std::nullopt;
  }
  for (const fs::path& dir : charsetDirs()) {
    const fs::path path = dir / (std::string(name) + ".json");
    std::ifstream input(path);
    if (!input) {
      continue;
    }
    const std::string json((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    const std::optional<std::string> glyphs = jsonStringField(json, "glyphs");
    if (!glyphs.has_value()) {
      throw std::invalid_argument("charset JSON missing glyphs: " + path.string());
    }
    return decodeCharset(*glyphs);
  }
  return std::nullopt;
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
    if (isBrailleCharset(charset) || presetRamp(charset).has_value()) {
      return true;
    }
    (void)decodeCharset(charset);
    return true;
  } catch (...) {
    return false;
  }
}

std::u32string resolveCharsetRamp(std::string_view charset) {
  if (const auto preset = presetRamp(charset); preset.has_value()) {
    return std::u32string(*preset);
  }
  if (isBrailleCharset(charset)) {
    throw std::invalid_argument("braille charset is a packed renderer");
  }
  if (const auto named = loadNamedCharset(charset); named.has_value()) {
    return *named;
  }
  return decodeCharset(charset);
}

bool isBrailleCharset(std::string_view charset) noexcept {
  return charset == "braille";
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
