#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>

namespace strok {

struct TerminalCaps {
  bool truecolor = false;
  int ansi_colors = 16;
  int unicode_version = 0;
  bool kitty_graphics = false;
  bool sixel = false;
  bool iterm_inline = false;
  bool font_has_octants = false;
  bool font_has_sextants = false;
  bool font_has_braille = false;
  std::string term_program;
};

struct TerminalCapsProbe {
  std::string term;
  std::string colorterm;
  std::string no_color;
  std::string term_program;
  std::string term_program_version;
  std::optional<std::filesystem::path> font_path;
  std::optional<std::string> override_spec;
};

TerminalCaps detectTerminalCaps(const TerminalCapsProbe& probe);
TerminalCaps detectTerminalCapsFromEnvironment(std::optional<std::filesystem::path> font_path, std::optional<std::string> override_spec);
std::string formatTerminalCaps(const TerminalCaps& caps);
std::string summarizeTerminalCaps(const TerminalCaps& caps);

}  // namespace strok
