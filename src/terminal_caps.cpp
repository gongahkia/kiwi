#include "terminal_caps.hpp"

#include <ft2build.h>
#include FT_FREETYPE_H

#include <algorithm>
#include <charconv>
#include <cctype>
#include <cstdlib>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>

namespace strok {
namespace {

bool hasValue(std::string_view value) noexcept {
  return !value.empty();
}

std::string getenvString(const char* key) {
  const char* value = std::getenv(key);
  return value == nullptr ? std::string{} : std::string(value);
}

std::string lower(std::string_view value) {
  std::string out(value);
  std::transform(out.begin(), out.end(), out.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return out;
}

bool containsLower(std::string_view value, std::string_view needle) {
  return lower(value).find(needle) != std::string::npos;
}

std::string_view trim(std::string_view value) {
  while (!value.empty() && (value.front() == ' ' || value.front() == '\t')) {
    value.remove_prefix(1);
  }
  while (!value.empty() && (value.back() == ' ' || value.back() == '\t')) {
    value.remove_suffix(1);
  }
  return value;
}

int parseInt(std::string_view value) {
  int parsed = 0;
  const auto* first = value.data();
  const auto* last = value.data() + value.size();
  const auto result = std::from_chars(first, last, parsed);
  if (result.ec != std::errc{} || result.ptr != last) {
    throw std::invalid_argument("invalid --caps integer: " + std::string(value));
  }
  return parsed;
}

std::string boolString(bool value) {
  return value ? "true" : "false";
}

void setTruecolor(TerminalCaps* caps, bool enabled) {
  caps->truecolor = enabled;
  if (enabled) {
    caps->ansi_colors = 24;
  } else if (caps->ansi_colors == 24) {
    caps->ansi_colors = 256;
  }
}

void applyAllowlist(std::string_view term_program, TerminalCaps* caps) {
  const std::string program = lower(term_program);
  if (program.empty()) {
    return;
  }
  if (program.find("kitty") != std::string::npos ||
      program.find("wezterm") != std::string::npos ||
      program.find("ghostty") != std::string::npos) {
    caps->kitty_graphics = true;
  }
  if (program.find("iterm") != std::string::npos) {
    caps->iterm_inline = true;
  }
  if (program.find("kitty") != std::string::npos ||
      program.find("wezterm") != std::string::npos ||
      program.find("ghostty") != std::string::npos ||
      program.find("iterm") != std::string::npos ||
      program.find("vscode") != std::string::npos ||
      program.find("visual studio code") != std::string::npos) {
    caps->unicode_version = std::max(caps->unicode_version, 16);
    setTruecolor(caps, true);
  }
}

void probeFontCmap(const std::filesystem::path& path, TerminalCaps* caps) {
  FT_Library library = nullptr;
  FT_Error error = FT_Init_FreeType(&library);
  if (error != 0) {
    throw std::runtime_error("failed to initialize FreeType");
  }

  FT_Face face = nullptr;
  error = FT_New_Face(library, path.string().c_str(), 0, &face);
  if (error != 0) {
    FT_Done_FreeType(library);
    throw std::runtime_error("failed to load font for caps probe: " + path.string());
  }

  caps->font_has_octants = FT_Get_Char_Index(face, 0x1CD00) != 0;
  caps->font_has_sextants = FT_Get_Char_Index(face, 0x1FB00) != 0;
  caps->font_has_braille = FT_Get_Char_Index(face, 0x2800) != 0;
  if (caps->font_has_octants) {
    caps->unicode_version = std::max(caps->unicode_version, 16);
  } else if (caps->font_has_sextants) {
    caps->unicode_version = std::max(caps->unicode_version, 13);
  }

  FT_Done_Face(face);
  FT_Done_FreeType(library);
}

void applyOverrideToken(std::string_view token, TerminalCaps* caps) {
  token = trim(token);
  if (token.empty()) {
    return;
  }
  const auto equals = token.find('=');
  if (equals != std::string_view::npos) {
    const std::string key = lower(trim(token.substr(0, equals)));
    const std::string_view value = trim(token.substr(equals + 1));
    if (key == "unicode") {
      caps->unicode_version = parseInt(value);
      return;
    }
    if (key == "ansi" || key == "colors" || key == "ansi-colors") {
      caps->ansi_colors = parseInt(value);
      caps->truecolor = caps->ansi_colors == 24;
      return;
    }
    throw std::invalid_argument("unknown --caps override: " + std::string(token));
  }

  const std::string value = lower(token);
  if (value == "truecolor") {
    setTruecolor(caps, true);
  } else if (value == "no-truecolor") {
    setTruecolor(caps, false);
  } else if (value == "kitty" || value == "kitty-graphics") {
    caps->kitty_graphics = true;
  } else if (value == "no-kitty" || value == "no-kitty-graphics") {
    caps->kitty_graphics = false;
  } else if (value == "sixel") {
    caps->sixel = true;
  } else if (value == "no-sixel") {
    caps->sixel = false;
  } else if (value == "iterm" || value == "iterm-inline") {
    caps->iterm_inline = true;
  } else if (value == "no-iterm" || value == "no-iterm-inline") {
    caps->iterm_inline = false;
  } else if (value == "octant" || value == "octants") {
    caps->font_has_octants = true;
  } else if (value == "no-octant" || value == "no-octants") {
    caps->font_has_octants = false;
  } else if (value == "sextant" || value == "sextants") {
    caps->font_has_sextants = true;
  } else if (value == "no-sextant" || value == "no-sextants") {
    caps->font_has_sextants = false;
  } else if (value == "braille") {
    caps->font_has_braille = true;
  } else if (value == "no-braille") {
    caps->font_has_braille = false;
  } else {
    throw std::invalid_argument("unknown --caps override: " + std::string(token));
  }
}

void applyOverrides(std::string_view spec, TerminalCaps* caps) {
  std::size_t start = 0;
  while (start <= spec.size()) {
    const std::size_t comma = spec.find(',', start);
    const std::string_view token = spec.substr(start, comma == std::string_view::npos ? std::string_view::npos : comma - start);
    applyOverrideToken(token, caps);
    if (comma == std::string_view::npos) {
      break;
    }
    start = comma + 1;
  }
}

}  // namespace

TerminalCaps detectTerminalCaps(const TerminalCapsProbe& probe) {
  TerminalCaps caps;
  caps.term_program = probe.term_program;

  const bool color_disabled = hasValue(probe.no_color);
  if (!color_disabled && (containsLower(probe.colorterm, "truecolor") || containsLower(probe.colorterm, "24bit"))) {
    caps.truecolor = true;
    caps.ansi_colors = 24;
  } else if (!color_disabled && containsLower(probe.term, "256")) {
    caps.ansi_colors = 256;
  }

  applyAllowlist(probe.term_program, &caps);
  if (color_disabled) {
    caps.truecolor = false;
    caps.ansi_colors = 0;
  }

  if (probe.font_path.has_value()) {
    probeFontCmap(*probe.font_path, &caps);
  }

  if (probe.override_spec.has_value()) {
    applyOverrides(*probe.override_spec, &caps);
  }

  return caps;
}

TerminalCaps detectTerminalCapsFromEnvironment(std::optional<std::filesystem::path> font_path, std::optional<std::string> override_spec) {
  return detectTerminalCaps(TerminalCapsProbe{
    .term = getenvString("TERM"),
    .colorterm = getenvString("COLORTERM"),
    .no_color = getenvString("NO_COLOR"),
    .term_program = getenvString("TERM_PROGRAM"),
    .term_program_version = getenvString("TERM_PROGRAM_VERSION"),
    .font_path = std::move(font_path),
    .override_spec = std::move(override_spec),
  });
}

std::string formatTerminalCaps(const TerminalCaps& caps) {
  std::ostringstream out;
  out << "truecolor=" << boolString(caps.truecolor) << '\n'
      << "ansi_colors=" << caps.ansi_colors << '\n'
      << "unicode_version=" << caps.unicode_version << '\n'
      << "kitty_graphics=" << boolString(caps.kitty_graphics) << '\n'
      << "sixel=" << boolString(caps.sixel) << '\n'
      << "iterm_inline=" << boolString(caps.iterm_inline) << '\n'
      << "font_has_octants=" << boolString(caps.font_has_octants) << '\n'
      << "font_has_sextants=" << boolString(caps.font_has_sextants) << '\n'
      << "font_has_braille=" << boolString(caps.font_has_braille) << '\n'
      << "term_program=" << caps.term_program << '\n';
  return out.str();
}

std::string summarizeTerminalCaps(const TerminalCaps& caps) {
  std::string summary = formatTerminalCaps(caps);
  std::replace(summary.begin(), summary.end(), '\n', ' ');
  while (!summary.empty() && summary.back() == ' ') {
    summary.pop_back();
  }
  return summary;
}

}  // namespace strok
