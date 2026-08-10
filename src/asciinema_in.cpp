#include "asciinema_in.hpp"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>

namespace strok {
namespace {

constexpr std::size_t kMaxJsonDepth = 32;
constexpr double kMicrosecondsPerSecond = 1000000.0;
constexpr double kFirstUnrepresentableInt64 = 9223372036854775808.0;

class JsonCursor {
 public:
  explicit JsonCursor(std::string_view text) : text_(text) {}

  void expect(char expected) {
    skipWhitespace();
    if (index_ >= text_.size() || text_[index_] != expected) {
      throw std::invalid_argument("invalid asciinema JSON");
    }
    ++index_;
  }

  bool consume(char expected) {
    skipWhitespace();
    if (index_ >= text_.size() || text_[index_] != expected) {
      return false;
    }
    ++index_;
    return true;
  }

  void requireEnd() {
    skipWhitespace();
    if (index_ != text_.size()) {
      throw std::invalid_argument("trailing asciinema JSON data");
    }
  }

  double parseNumber() {
    skipWhitespace();
    const std::size_t first = index_;
    if (index_ < text_.size() && text_[index_] == '-') {
      ++index_;
    }
    if (index_ >= text_.size()) {
      throw std::invalid_argument("invalid asciinema number");
    }
    if (text_[index_] == '0') {
      ++index_;
      if (index_ < text_.size() && isDigit(text_[index_])) {
        throw std::invalid_argument("invalid asciinema number");
      }
    } else if (text_[index_] >= '1' && text_[index_] <= '9') {
      do {
        ++index_;
      } while (index_ < text_.size() && isDigit(text_[index_]));
    } else {
      throw std::invalid_argument("invalid asciinema number");
    }
    if (index_ < text_.size() && text_[index_] == '.') {
      ++index_;
      const std::size_t fractional_first = index_;
      while (index_ < text_.size() && isDigit(text_[index_])) {
        ++index_;
      }
      if (index_ == fractional_first) {
        throw std::invalid_argument("invalid asciinema number");
      }
    }
    if (index_ < text_.size() && (text_[index_] == 'e' || text_[index_] == 'E')) {
      ++index_;
      if (index_ < text_.size() && (text_[index_] == '+' || text_[index_] == '-')) {
        ++index_;
      }
      const std::size_t exponent_first = index_;
      while (index_ < text_.size() && isDigit(text_[index_])) {
        ++index_;
      }
      if (index_ == exponent_first) {
        throw std::invalid_argument("invalid asciinema number");
      }
    }

    const std::string number(text_.substr(first, index_ - first));
    char* last = nullptr;
    const double value = std::strtod(number.c_str(), &last);
    if (last != number.c_str() + number.size() || !std::isfinite(value)) {
      throw std::invalid_argument("invalid asciinema number");
    }
    return value;
  }

  std::string parseString() {
    expect('"');
    std::string result;
    while (index_ < text_.size()) {
      const unsigned char character = static_cast<unsigned char>(text_[index_]);
      if (character == '"') {
        ++index_;
        return result;
      }
      if (character < 0x20U) {
        throw std::invalid_argument("unescaped control character in asciinema string");
      }
      if (character != '\\') {
        if (character < 0x80U) {
          result.push_back(static_cast<char>(character));
          ++index_;
        } else {
          appendRawUtf8(&result);
        }
        continue;
      }

      ++index_;
      if (index_ >= text_.size()) {
        throw std::invalid_argument("unterminated asciinema escape");
      }
      switch (text_[index_++]) {
        case '"': result.push_back('"'); break;
        case '\\': result.push_back('\\'); break;
        case '/': result.push_back('/'); break;
        case 'b': result.push_back('\b'); break;
        case 'f': result.push_back('\f'); break;
        case 'n': result.push_back('\n'); break;
        case 'r': result.push_back('\r'); break;
        case 't': result.push_back('\t'); break;
        case 'u': appendEscapedUnicode(&result); break;
        default: throw std::invalid_argument("unsupported asciinema escape");
      }
    }
    throw std::invalid_argument("unterminated asciinema string");
  }

  void skipValue() {
    skipValue(0);
  }

 private:
  static bool isDigit(char value) noexcept {
    return value >= '0' && value <= '9';
  }

  static int hexValue(char value) noexcept {
    if (value >= '0' && value <= '9') {
      return value - '0';
    }
    if (value >= 'a' && value <= 'f') {
      return value - 'a' + 10;
    }
    if (value >= 'A' && value <= 'F') {
      return value - 'A' + 10;
    }
    return -1;
  }

  void skipWhitespace() {
    while (index_ < text_.size()) {
      const char value = text_[index_];
      if (value != ' ' && value != '\t' && value != '\r' && value != '\n') {
        return;
      }
      ++index_;
    }
  }

  uint32_t parseUnicodeCodeUnit() {
    if (index_ + 4U > text_.size()) {
      throw std::invalid_argument("short asciinema unicode escape");
    }
    uint32_t code_unit = 0;
    for (int digit = 0; digit < 4; ++digit) {
      const int value = hexValue(text_[index_++]);
      if (value < 0) {
        throw std::invalid_argument("invalid asciinema unicode escape");
      }
      code_unit = (code_unit << 4U) | static_cast<uint32_t>(value);
    }
    return code_unit;
  }

  static void appendUtf8(std::string* output, uint32_t codepoint) {
    if (codepoint <= 0x7fU) {
      output->push_back(static_cast<char>(codepoint));
    } else if (codepoint <= 0x7ffU) {
      output->push_back(static_cast<char>(0xc0U | (codepoint >> 6U)));
      output->push_back(static_cast<char>(0x80U | (codepoint & 0x3fU)));
    } else if (codepoint <= 0xffffU) {
      output->push_back(static_cast<char>(0xe0U | (codepoint >> 12U)));
      output->push_back(static_cast<char>(0x80U | ((codepoint >> 6U) & 0x3fU)));
      output->push_back(static_cast<char>(0x80U | (codepoint & 0x3fU)));
    } else {
      output->push_back(static_cast<char>(0xf0U | (codepoint >> 18U)));
      output->push_back(static_cast<char>(0x80U | ((codepoint >> 12U) & 0x3fU)));
      output->push_back(static_cast<char>(0x80U | ((codepoint >> 6U) & 0x3fU)));
      output->push_back(static_cast<char>(0x80U | (codepoint & 0x3fU)));
    }
  }

  void appendEscapedUnicode(std::string* output) {
    uint32_t codepoint = parseUnicodeCodeUnit();
    if (codepoint >= 0xd800U && codepoint <= 0xdbffU) {
      if (index_ + 2U > text_.size() || text_[index_] != '\\' || text_[index_ + 1U] != 'u') {
        throw std::invalid_argument("unpaired asciinema high surrogate");
      }
      index_ += 2U;
      const uint32_t low = parseUnicodeCodeUnit();
      if (low < 0xdc00U || low > 0xdfffU) {
        throw std::invalid_argument("invalid asciinema surrogate pair");
      }
      codepoint = 0x10000U + ((codepoint - 0xd800U) << 10U) + (low - 0xdc00U);
    } else if (codepoint >= 0xdc00U && codepoint <= 0xdfffU) {
      throw std::invalid_argument("unpaired asciinema low surrogate");
    }
    appendUtf8(output, codepoint);
  }

  void appendRawUtf8(std::string* output) {
    const std::size_t first = index_;
    const unsigned char lead = static_cast<unsigned char>(text_[index_]);
    int continuation_count = 0;
    uint32_t codepoint = 0;
    uint32_t minimum = 0;
    if (lead >= 0xc2U && lead <= 0xdfU) {
      continuation_count = 1;
      codepoint = lead & 0x1fU;
      minimum = 0x80U;
    } else if (lead >= 0xe0U && lead <= 0xefU) {
      continuation_count = 2;
      codepoint = lead & 0x0fU;
      minimum = 0x800U;
    } else if (lead >= 0xf0U && lead <= 0xf4U) {
      continuation_count = 3;
      codepoint = lead & 0x07U;
      minimum = 0x10000U;
    } else {
      throw std::invalid_argument("invalid UTF-8 in asciinema string");
    }
    if (index_ + static_cast<std::size_t>(continuation_count) >= text_.size()) {
      throw std::invalid_argument("truncated UTF-8 in asciinema string");
    }
    for (int offset = 1; offset <= continuation_count; ++offset) {
      const unsigned char byte = static_cast<unsigned char>(text_[index_ + static_cast<std::size_t>(offset)]);
      if ((byte & 0xc0U) != 0x80U) {
        throw std::invalid_argument("invalid UTF-8 in asciinema string");
      }
      codepoint = (codepoint << 6U) | (byte & 0x3fU);
    }
    if (codepoint < minimum || (codepoint >= 0xd800U && codepoint <= 0xdfffU) || codepoint > 0x10ffffU) {
      throw std::invalid_argument("invalid UTF-8 in asciinema string");
    }
    index_ += static_cast<std::size_t>(continuation_count + 1);
    output->append(text_.substr(first, index_ - first));
  }

  void expectLiteral(std::string_view literal) {
    if (text_.substr(index_, literal.size()) != literal) {
      throw std::invalid_argument("invalid asciinema JSON value");
    }
    index_ += literal.size();
  }

  void skipValue(std::size_t depth) {
    if (depth >= kMaxJsonDepth) {
      throw std::invalid_argument("asciinema JSON nesting limit exceeded");
    }
    skipWhitespace();
    if (index_ >= text_.size()) {
      throw std::invalid_argument("missing asciinema JSON value");
    }
    const char value = text_[index_];
    if (value == '"') {
      (void)parseString();
      return;
    }
    if (value == '-' || isDigit(value)) {
      (void)parseNumber();
      return;
    }
    if (value == 't') {
      expectLiteral("true");
      return;
    }
    if (value == 'f') {
      expectLiteral("false");
      return;
    }
    if (value == 'n') {
      expectLiteral("null");
      return;
    }
    if (value == '[') {
      ++index_;
      if (consume(']')) {
        return;
      }
      while (true) {
        skipValue(depth + 1U);
        if (consume(']')) {
          return;
        }
        expect(',');
      }
    }
    if (value == '{') {
      ++index_;
      if (consume('}')) {
        return;
      }
      while (true) {
        (void)parseString();
        expect(':');
        skipValue(depth + 1U);
        if (consume('}')) {
          return;
        }
        expect(',');
      }
    }
    throw std::invalid_argument("invalid asciinema JSON value");
  }

  std::string_view text_;
  std::size_t index_ = 0;
};

int parseHeaderInteger(JsonCursor* cursor, std::string_view key) {
  const double value = cursor->parseNumber();
  if (value < 0.0 || value > static_cast<double>(std::numeric_limits<int>::max()) || std::trunc(value) != value) {
    throw std::invalid_argument("invalid asciinema integer key: " + std::string(key));
  }
  return static_cast<int>(value);
}

double parseEventTime(JsonCursor* cursor) {
  const double time = cursor->parseNumber();
  const double microseconds = std::round(time * kMicrosecondsPerSecond);
  if (time < 0.0 || !std::isfinite(microseconds) || microseconds < 0.0 || microseconds >= kFirstUnrepresentableInt64) {
    throw std::invalid_argument("invalid asciinema event time");
  }
  return time;
}

}  // namespace

AsciinemaHeader parseAsciinemaHeader(std::string_view line) {
  JsonCursor cursor(line);
  cursor.expect('{');
  std::optional<int> version;
  std::optional<int> width;
  std::optional<int> height;
  if (!cursor.consume('}')) {
    while (true) {
      const std::string key = cursor.parseString();
      cursor.expect(':');
      if (key == "version") {
        if (version.has_value()) {
          throw std::invalid_argument("duplicate asciinema header key: version");
        }
        version = parseHeaderInteger(&cursor, key);
      } else if (key == "width") {
        if (width.has_value()) {
          throw std::invalid_argument("duplicate asciinema header key: width");
        }
        width = parseHeaderInteger(&cursor, key);
      } else if (key == "height") {
        if (height.has_value()) {
          throw std::invalid_argument("duplicate asciinema header key: height");
        }
        height = parseHeaderInteger(&cursor, key);
      } else {
        cursor.skipValue();
      }
      if (cursor.consume('}')) {
        break;
      }
      cursor.expect(',');
    }
  }
  cursor.requireEnd();
  if (!version.has_value() || !width.has_value() || !height.has_value()) {
    throw std::invalid_argument("missing asciinema header key");
  }
  if (*version != 2 || *width <= 0 || *height <= 0) {
    throw std::invalid_argument("unsupported asciinema header");
  }
  return AsciinemaHeader{.version = *version, .width = *width, .height = *height};
}

AsciinemaEvent parseAsciinemaEvent(std::string_view line) {
  JsonCursor cursor(line);
  cursor.expect('[');
  const double time = parseEventTime(&cursor);
  cursor.expect(',');
  std::string type = cursor.parseString();
  cursor.expect(',');
  std::string data = cursor.parseString();
  cursor.expect(']');
  cursor.requireEnd();
  return AsciinemaEvent{.time = time, .type = std::move(type), .data = std::move(data)};
}

}  // namespace strok
