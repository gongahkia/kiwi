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

strok::CliOptions options(std::string render_mode) {
  strok::CliOptions opts;
  opts.render_mode = std::move(render_mode);
  return opts;
}

void expectResolution(const strok::RenderModeResolution& actual,
                      strok::ResolvedRenderMode mode,
                      strok::GraphicsProtocol protocol,
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
      strok::TerminalCaps caps;
      strok::ResolvedRenderMode mode;
      strok::GraphicsProtocol protocol;
      bool degraded = false;
      const char* label = "";
    };
    const std::vector<Case> cases {
      Case{.requested = "text", .caps = {}, .mode = strok::ResolvedRenderMode::Text, .protocol = strok::GraphicsProtocol::None, .degraded = false, .label = "text/no-caps"},
      Case{.requested = "text", .caps = strok::TerminalCaps{.kitty_graphics = true}, .mode = strok::ResolvedRenderMode::Text, .protocol = strok::GraphicsProtocol::None, .degraded = false, .label = "text/kitty"},
      Case{.requested = "auto", .caps = {}, .mode = strok::ResolvedRenderMode::Text, .protocol = strok::GraphicsProtocol::None, .degraded = true, .label = "auto/no-caps"},
      Case{.requested = "auto", .caps = strok::TerminalCaps{.kitty_graphics = true}, .mode = strok::ResolvedRenderMode::Pixel, .protocol = strok::GraphicsProtocol::Kitty, .degraded = false, .label = "auto/kitty"},
      Case{.requested = "auto", .caps = strok::TerminalCaps{.sixel = true}, .mode = strok::ResolvedRenderMode::Pixel, .protocol = strok::GraphicsProtocol::Sixel, .degraded = false, .label = "auto/sixel"},
      Case{.requested = "auto", .caps = strok::TerminalCaps{.iterm_inline = true}, .mode = strok::ResolvedRenderMode::Pixel, .protocol = strok::GraphicsProtocol::ITermInline, .degraded = false, .label = "auto/iterm"},
      Case{.requested = "pixel", .caps = {}, .mode = strok::ResolvedRenderMode::Text, .protocol = strok::GraphicsProtocol::None, .degraded = true, .label = "pixel/no-caps"},
      Case{.requested = "pixel", .caps = strok::TerminalCaps{.kitty_graphics = true}, .mode = strok::ResolvedRenderMode::Pixel, .protocol = strok::GraphicsProtocol::Kitty, .degraded = false, .label = "pixel/kitty"},
      Case{.requested = "pixel", .caps = strok::TerminalCaps{.sixel = true}, .mode = strok::ResolvedRenderMode::Pixel, .protocol = strok::GraphicsProtocol::Sixel, .degraded = false, .label = "pixel/sixel"},
      Case{.requested = "pixel", .caps = strok::TerminalCaps{.iterm_inline = true}, .mode = strok::ResolvedRenderMode::Pixel, .protocol = strok::GraphicsProtocol::ITermInline, .degraded = false, .label = "pixel/iterm"},
      Case{.requested = "hybrid", .caps = {}, .mode = strok::ResolvedRenderMode::Text, .protocol = strok::GraphicsProtocol::None, .degraded = true, .label = "hybrid/no-caps"},
      Case{.requested = "hybrid", .caps = strok::TerminalCaps{.kitty_graphics = true}, .mode = strok::ResolvedRenderMode::Hybrid, .protocol = strok::GraphicsProtocol::Kitty, .degraded = false, .label = "hybrid/kitty"},
      Case{.requested = "hybrid", .caps = strok::TerminalCaps{.sixel = true}, .mode = strok::ResolvedRenderMode::Hybrid, .protocol = strok::GraphicsProtocol::Sixel, .degraded = false, .label = "hybrid/sixel"},
      Case{.requested = "hybrid", .caps = strok::TerminalCaps{.iterm_inline = true}, .mode = strok::ResolvedRenderMode::Hybrid, .protocol = strok::GraphicsProtocol::ITermInline, .degraded = false, .label = "hybrid/iterm"},
    };
    for (const Case& test_case : cases) {
      expectResolution(strok::resolveRenderMode(options(test_case.requested), test_case.caps),
                       test_case.mode,
                       test_case.protocol,
                       test_case.degraded,
                       test_case.label);
    }
  }

  {
    const auto resolved = strok::resolveRenderMode(options("text"), strok::TerminalCaps{.kitty_graphics = true});
    expect(resolved.mode == strok::ResolvedRenderMode::Text, "text stays text");
    expect(resolved.protocol == strok::GraphicsProtocol::None, "text has no protocol");
    expect(!resolved.degraded_to_text, "text does not degrade");
  }

  {
    const auto resolved = strok::resolveRenderMode(options("auto"), strok::TerminalCaps{});
    expect(resolved.mode == strok::ResolvedRenderMode::Text, "auto without graphics falls back text");
    expect(resolved.protocol == strok::GraphicsProtocol::None, "auto without graphics has no protocol");
    expect(resolved.degraded_to_text, "auto without graphics records degradation");
  }

  {
    const auto resolved = strok::resolveRenderMode(options("auto"), strok::TerminalCaps{.kitty_graphics = true});
    expect(resolved.mode == strok::ResolvedRenderMode::Pixel, "auto kitty picks pixel");
    expect(resolved.protocol == strok::GraphicsProtocol::Kitty, "auto kitty protocol");
  }

  {
    const auto resolved = strok::resolveRenderMode(options("auto"), strok::TerminalCaps{.sixel = true});
    expect(resolved.mode == strok::ResolvedRenderMode::Pixel, "auto sixel picks pixel");
    expect(resolved.protocol == strok::GraphicsProtocol::Sixel, "auto sixel protocol");
  }

  {
    const auto resolved = strok::resolveRenderMode(options("auto"), strok::TerminalCaps{.iterm_inline = true});
    expect(resolved.mode == strok::ResolvedRenderMode::Pixel, "auto iTerm picks pixel");
    expect(resolved.protocol == strok::GraphicsProtocol::ITermInline, "auto iTerm protocol");
  }

  {
    const auto resolved = strok::resolveRenderMode(options("pixel"), strok::TerminalCaps{});
    expect(resolved.mode == strok::ResolvedRenderMode::Text, "pixel without graphics falls back text");
    expect(resolved.degraded_to_text, "pixel without graphics records degradation");
  }

  {
    const auto resolved = strok::resolveRenderMode(options("hybrid"), strok::TerminalCaps{.kitty_graphics = true});
    expect(resolved.mode == strok::ResolvedRenderMode::Hybrid, "hybrid kitty stays hybrid");
    expect(resolved.protocol == strok::GraphicsProtocol::Kitty, "hybrid kitty protocol");
  }

  {
    const auto protocol = strok::bestGraphicsProtocol(strok::TerminalCaps{.kitty_graphics = true, .sixel = true, .iterm_inline = true});
    expect(protocol == strok::GraphicsProtocol::Kitty, "kitty preferred over other protocols");
    expect(strok::toString(protocol) == "kitty", "protocol string");
    expect(strok::toString(strok::ResolvedRenderMode::Hybrid) == "hybrid", "mode string");
  }
}
