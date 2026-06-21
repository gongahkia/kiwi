#include "asciinema_in.hpp"

#include <cstdint>
#include <cstdlib>
#include <stdexcept>
#include <string>

namespace contourtty {
namespace {

void skipSpace(std::string_view line, std::size_t* index) {
  while (*index < line.size() && (line[*index] == ' ' || line[*index] == '\t' || line[*index] == '\r')) {
    ++(*index);
  }
}

void expectChar(std::string_view line, std::size_t* index, char expected) {
  skipSpace(line, index);
  if (*index >= line.size() || line[*index] != expected) {
    throw std::invalid_argument("invalid asciinema line");
  }
  ++(*index);
}

double parseNumber(std::string_view line, std::size_t* index) {
  skipSpace(line, index);
  const char* first = line.data() + *index;
  char* last = nullptr;
  const double value = std::strtod(first, &last);
  if (last == first) {
    throw std::invalid_argument("invalid asciinema number");
  }
  *index = static_cast<std::size_t>(last - line.data());
  return value;
}

std::string parseJsonString(std::string_view line, std::size_t* index) {
  skipSpace(line, index);
  if (*index >= line.size() || line[*index] != '"') {
    throw std::invalid_argument("invalid asciinema string");
  }
  ++(*index);
  std::string out;
  while (*index < line.size()) {
    const char ch = line[(*index)++];
    if (ch == '"') {
      return out;
    }
    if (ch != '\\') {
      out.push_back(ch);
      continue;
    }
    if (*index >= line.size()) {
      throw std::invalid_argument("unterminated asciinema escape");
    }
    const char escaped = line[(*index)++];
    switch (escaped) {
      case '"':
      case '\\':
      case '/':
        out.push_back(escaped);
        break;
      case 'b':
        out.push_back('\b');
        break;
      case 'f':
        out.push_back('\f');
        break;
      case 'n':
        out.push_back('\n');
        break;
      case 'r':
        out.push_back('\r');
        break;
      case 't':
        out.push_back('\t');
        break;
      case 'u': {
        if (*index + 4 > line.size()) {
          throw std::invalid_argument("short asciinema unicode escape");
        }
        uint32_t codepoint = 0;
        for (int i = 0; i < 4; ++i) {
          const char hex = line[(*index)++];
          codepoint *= 16;
          if (hex >= '0' && hex <= '9') {
            codepoint += static_cast<uint32_t>(hex - '0');
          } else if (hex >= 'a' && hex <= 'f') {
            codepoint += static_cast<uint32_t>(hex - 'a' + 10);
          } else if (hex >= 'A' && hex <= 'F') {
            codepoint += static_cast<uint32_t>(hex - 'A' + 10);
          } else {
            throw std::invalid_argument("invalid asciinema unicode escape");
          }
        }
        if (codepoint <= 0x7fU) {
          out.push_back(static_cast<char>(codepoint));
        } else if (codepoint <= 0x7ffU) {
          out.push_back(static_cast<char>(0xc0U | (codepoint >> 6U)));
          out.push_back(static_cast<char>(0x80U | (codepoint & 0x3fU)));
        } else {
          out.push_back(static_cast<char>(0xe0U | (codepoint >> 12U)));
          out.push_back(static_cast<char>(0x80U | ((codepoint >> 6U) & 0x3fU)));
          out.push_back(static_cast<char>(0x80U | (codepoint & 0x3fU)));
        }
        break;
      }
      default:
        throw std::invalid_argument("unsupported asciinema escape");
    }
  }
  throw std::invalid_argument("unterminated asciinema string");
}

int parseObjectInt(std::string_view line, std::string_view key) {
  const std::string needle = "\"" + std::string(key) + "\"";
  const std::size_t key_pos = line.find(needle);
  if (key_pos == std::string_view::npos) {
    throw std::invalid_argument("missing asciinema header key: " + std::string(key));
  }
  const std::size_t colon = line.find(':', key_pos + needle.size());
  if (colon == std::string_view::npos) {
    throw std::invalid_argument("invalid asciinema header key: " + std::string(key));
  }
  std::size_t index = colon + 1;
  const double value = parseNumber(line, &index);
  if (value < 0.0 || value != static_cast<int>(value)) {
    throw std::invalid_argument("invalid asciinema integer key: " + std::string(key));
  }
  return static_cast<int>(value);
}

}  // namespace

AsciinemaHeader parseAsciinemaHeader(std::string_view line) {
  AsciinemaHeader header{
    .version = parseObjectInt(line, "version"),
    .width = parseObjectInt(line, "width"),
    .height = parseObjectInt(line, "height"),
  };
  if (header.version != 2 || header.width <= 0 || header.height <= 0) {
    throw std::invalid_argument("unsupported asciinema header");
  }
  return header;
}

AsciinemaEvent parseAsciinemaEvent(std::string_view line) {
  std::size_t index = 0;
  expectChar(line, &index, '[');
  const double time = parseNumber(line, &index);
  expectChar(line, &index, ',');
  std::string type = parseJsonString(line, &index);
  expectChar(line, &index, ',');
  std::string data = parseJsonString(line, &index);
  expectChar(line, &index, ']');
  skipSpace(line, &index);
  if (index != line.size()) {
    throw std::invalid_argument("trailing asciinema event data");
  }
  return AsciinemaEvent{.time = time, .type = std::move(type), .data = std::move(data)};
}

}  // namespace contourtty
