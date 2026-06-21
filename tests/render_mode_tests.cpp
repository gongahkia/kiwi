#include "render_mode.hpp"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

contourtty::CliOptions options(std::string render_mode) {
  contourtty::CliOptions opts;
  opts.render_mode = std::move(render_mode);
  return opts;
}

void expectResolution(const contourtty::RenderModeResolution& actual,
                      contourtty::ResolvedRenderMode mode,
                      contourtty::GraphicsProtocol protocol,
                      bool degraded,
                      const char* label) {
  expect(actual.mode == mode, label);
  expect(actual.protocol == protocol, label);
  expect(actual.degraded_to_text == degraded, label);
}

}  // namespace

int main() {
  {
    struct Case {
      std::string requested;
      contourtty::TerminalCaps caps;
      contourtty::ResolvedRenderMode mode;
      contourtty::GraphicsProtocol protocol;
      bool degraded = false;
      const char* label = "";
    };
    const std::vector<Case> cases {
      Case{.requested = "text", .caps = {}, .mode = contourtty::ResolvedRenderMode::Text, .protocol = contourtty::GraphicsProtocol::None, .degraded = false, .label = "text/no-caps"},
      Case{.requested = "text", .caps = contourtty::TerminalCaps{.kitty_graphics = true}, .mode = contourtty::ResolvedRenderMode::Text, .protocol = contourtty::GraphicsProtocol::None, .degraded = false, .label = "text/kitty"},
      Case{.requested = "auto", .caps = {}, .mode = contourtty::ResolvedRenderMode::Text, .protocol = contourtty::GraphicsProtocol::None, .degraded = true, .label = "auto/no-caps"},
      Case{.requested = "auto", .caps = contourtty::TerminalCaps{.kitty_graphics = true}, .mode = contourtty::ResolvedRenderMode::Pixel, .protocol = contourtty::GraphicsProtocol::Kitty, .degraded = false, .label = "auto/kitty"},
      Case{.requested = "auto", .caps = contourtty::TerminalCaps{.sixel = true}, .mode = contourtty::ResolvedRenderMode::Pixel, .protocol = contourtty::GraphicsProtocol::Sixel, .degraded = false, .label = "auto/sixel"},
      Case{.requested = "auto", .caps = contourtty::TerminalCaps{.iterm_inline = true}, .mode = contourtty::ResolvedRenderMode::Pixel, .protocol = contourtty::GraphicsProtocol::ITermInline, .degraded = false, .label = "auto/iterm"},
      Case{.requested = "pixel", .caps = {}, .mode = contourtty::ResolvedRenderMode::Text, .protocol = contourtty::GraphicsProtocol::None, .degraded = true, .label = "pixel/no-caps"},
      Case{.requested = "pixel", .caps = contourtty::TerminalCaps{.kitty_graphics = true}, .mode = contourtty::ResolvedRenderMode::Pixel, .protocol = contourtty::GraphicsProtocol::Kitty, .degraded = false, .label = "pixel/kitty"},
      Case{.requested = "pixel", .caps = contourtty::TerminalCaps{.sixel = true}, .mode = contourtty::ResolvedRenderMode::Pixel, .protocol = contourtty::GraphicsProtocol::Sixel, .degraded = false, .label = "pixel/sixel"},
      Case{.requested = "pixel", .caps = contourtty::TerminalCaps{.iterm_inline = true}, .mode = contourtty::ResolvedRenderMode::Pixel, .protocol = contourtty::GraphicsProtocol::ITermInline, .degraded = false, .label = "pixel/iterm"},
      Case{.requested = "hybrid", .caps = {}, .mode = contourtty::ResolvedRenderMode::Text, .protocol = contourtty::GraphicsProtocol::None, .degraded = true, .label = "hybrid/no-caps"},
      Case{.requested = "hybrid", .caps = contourtty::TerminalCaps{.kitty_graphics = true}, .mode = contourtty::ResolvedRenderMode::Hybrid, .protocol = contourtty::GraphicsProtocol::Kitty, .degraded = false, .label = "hybrid/kitty"},
      Case{.requested = "hybrid", .caps = contourtty::TerminalCaps{.sixel = true}, .mode = contourtty::ResolvedRenderMode::Hybrid, .protocol = contourtty::GraphicsProtocol::Sixel, .degraded = false, .label = "hybrid/sixel"},
      Case{.requested = "hybrid", .caps = contourtty::TerminalCaps{.iterm_inline = true}, .mode = contourtty::ResolvedRenderMode::Hybrid, .protocol = contourtty::GraphicsProtocol::ITermInline, .degraded = false, .label = "hybrid/iterm"},
    };
    for (const Case& test_case : cases) {
      expectResolution(contourtty::resolveRenderMode(options(test_case.requested), test_case.caps),
                       test_case.mode,
                       test_case.protocol,
                       test_case.degraded,
                       test_case.label);
    }
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("text"), contourtty::TerminalCaps{.kitty_graphics = true});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Text, "text stays text");
    expect(resolved.protocol == contourtty::GraphicsProtocol::None, "text has no protocol");
    expect(!resolved.degraded_to_text, "text does not degrade");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("auto"), contourtty::TerminalCaps{});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Text, "auto without graphics falls back text");
    expect(resolved.protocol == contourtty::GraphicsProtocol::None, "auto without graphics has no protocol");
    expect(resolved.degraded_to_text, "auto without graphics records degradation");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("auto"), contourtty::TerminalCaps{.kitty_graphics = true});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Pixel, "auto kitty picks pixel");
    expect(resolved.protocol == contourtty::GraphicsProtocol::Kitty, "auto kitty protocol");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("auto"), contourtty::TerminalCaps{.sixel = true});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Pixel, "auto sixel picks pixel");
    expect(resolved.protocol == contourtty::GraphicsProtocol::Sixel, "auto sixel protocol");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("auto"), contourtty::TerminalCaps{.iterm_inline = true});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Pixel, "auto iTerm picks pixel");
    expect(resolved.protocol == contourtty::GraphicsProtocol::ITermInline, "auto iTerm protocol");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("pixel"), contourtty::TerminalCaps{});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Text, "pixel without graphics falls back text");
    expect(resolved.degraded_to_text, "pixel without graphics records degradation");
  }

  {
    const auto resolved = contourtty::resolveRenderMode(options("hybrid"), contourtty::TerminalCaps{.kitty_graphics = true});
    expect(resolved.mode == contourtty::ResolvedRenderMode::Hybrid, "hybrid kitty stays hybrid");
    expect(resolved.protocol == contourtty::GraphicsProtocol::Kitty, "hybrid kitty protocol");
  }

  {
    const auto protocol = contourtty::bestGraphicsProtocol(contourtty::TerminalCaps{.kitty_graphics = true, .sixel = true, .iterm_inline = true});
    expect(protocol == contourtty::GraphicsProtocol::Kitty, "kitty preferred over other protocols");
    expect(contourtty::toString(protocol) == "kitty", "protocol string");
    expect(contourtty::toString(contourtty::ResolvedRenderMode::Hybrid) == "hybrid", "mode string");
  }
}
