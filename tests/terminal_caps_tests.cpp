#include "terminal_caps.hpp"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <vector>

namespace {

namespace fs = std::filesystem;

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

std::vector<fs::path> fontCandidates() {
  return {
    "/System/Library/Fonts/Apple Braille Outline 6 Dot.ttf",
    "/System/Library/Fonts/Apple Braille.ttf",
    "/System/Library/Fonts/SFNSMono.ttf",
    "/System/Library/Fonts/Supplemental/Menlo.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
  };
}

std::optional<fs::path> findFont() {
  const std::vector<fs::path> candidates {
    "/System/Library/Fonts/SFNSMono.ttf",
    "/System/Library/Fonts/Supplemental/Menlo.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/dejavu/DejaVuSansMono.ttf",
  };
  for (const fs::path& path : candidates) {
    if (fs::exists(path)) {
      return path;
    }
  }
  return std::nullopt;
}

}  // namespace

int main() {
  {
    const auto start = std::chrono::steady_clock::now();
    const contourtty::TerminalCaps caps = contourtty::detectTerminalCaps(contourtty::TerminalCapsProbe{
      .term = "xterm-256color",
      .colorterm = "truecolor",
    });
    const auto elapsed = std::chrono::steady_clock::now() - start;
    expect(std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count() < 5, "env caps probe under 5ms");
    expect(caps.truecolor, "truecolor detected");
    expect(caps.ansi_colors == 24, "truecolor ansi tier");
  }

  {
    const contourtty::TerminalCaps caps = contourtty::detectTerminalCaps(contourtty::TerminalCapsProbe{
      .term = "xterm-256color",
      .colorterm = "truecolor",
      .no_color = "1",
      .term_program = "WezTerm",
    });
    expect(!caps.truecolor, "NO_COLOR disables truecolor");
    expect(caps.ansi_colors == 0, "NO_COLOR disables ansi colors");
    expect(caps.unicode_version == 16, "allowlist still records unicode");
  }

  {
    const contourtty::TerminalCaps caps = contourtty::detectTerminalCaps(contourtty::TerminalCapsProbe{
      .term = "screen-256color",
    });
    expect(!caps.truecolor, "256 color is not truecolor");
    expect(caps.ansi_colors == 256, "TERM 256 detected");
  }

  {
    const contourtty::TerminalCaps caps = contourtty::detectTerminalCaps(contourtty::TerminalCapsProbe{
      .term_program = "kitty",
    });
    expect(caps.truecolor, "kitty truecolor allowlist");
    expect(caps.unicode_version == 16, "kitty unicode allowlist");
    expect(caps.kitty_graphics, "kitty graphics allowlist");
  }

  {
    const contourtty::TerminalCaps caps = contourtty::detectTerminalCaps(contourtty::TerminalCapsProbe{
      .override_spec = "unicode=13,sextant,truecolor,no-kitty,sixel",
    });
    expect(caps.unicode_version == 13, "override unicode");
    expect(caps.font_has_sextants, "override sextants");
    expect(caps.truecolor && caps.ansi_colors == 24, "override truecolor");
    expect(!caps.kitty_graphics, "override no kitty");
    expect(caps.sixel, "override sixel");
  }

  {
    bool threw = false;
    try {
      (void)contourtty::detectTerminalCaps(contourtty::TerminalCapsProbe{
        .override_spec = "unknown",
      });
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "unknown override rejected");
  }

  {
    bool found_braille_font = false;
    for (const fs::path& path : fontCandidates()) {
      if (!fs::exists(path)) {
        continue;
      }
      const contourtty::TerminalCaps caps = contourtty::detectTerminalCaps(contourtty::TerminalCapsProbe{
        .font_path = path,
      });
      if (caps.font_has_braille) {
        found_braille_font = true;
        break;
      }
    }
    if (findFont().has_value()) {
      expect(found_braille_font || !fs::exists("/System/Library/Fonts/Apple Braille Outline 6 Dot.ttf"), "font cmap detects braille when braille font is present");
    }
  }

  {
    const contourtty::TerminalCaps caps = contourtty::TerminalCaps{
      .truecolor = true,
      .ansi_colors = 24,
      .unicode_version = 16,
      .font_has_octants = true,
      .term_program = "Ghostty",
    };
    const std::string dump = contourtty::formatTerminalCaps(caps);
    expect(dump.find("truecolor=true\n") != std::string::npos, "format truecolor");
    expect(dump.find("unicode_version=16\n") != std::string::npos, "format unicode");
    expect(contourtty::summarizeTerminalCaps(caps).find('\n') == std::string::npos, "summary one line");
  }
}
