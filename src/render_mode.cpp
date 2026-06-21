#include "render_mode.hpp"

namespace contourtty {

GraphicsProtocol bestGraphicsProtocol(const TerminalCaps& caps) {
  if (caps.kitty_graphics) {
    return GraphicsProtocol::Kitty;
  }
  if (caps.sixel) {
    return GraphicsProtocol::Sixel;
  }
  if (caps.iterm_inline) {
    return GraphicsProtocol::ITermInline;
  }
  return GraphicsProtocol::None;
}

RenderModeResolution resolveRenderMode(const CliOptions& options, const TerminalCaps& caps) {
  const GraphicsProtocol protocol = bestGraphicsProtocol(caps);
  if (options.render_mode == "text") {
    return RenderModeResolution{};
  }
  if (options.render_mode == "auto") {
    if (protocol == GraphicsProtocol::None) {
      return RenderModeResolution{.degraded_to_text = true};
    }
    return RenderModeResolution{.mode = ResolvedRenderMode::Pixel, .protocol = protocol};
  }
  if (protocol == GraphicsProtocol::None) {
    return RenderModeResolution{.degraded_to_text = true};
  }
  if (options.render_mode == "pixel") {
    return RenderModeResolution{.mode = ResolvedRenderMode::Pixel, .protocol = protocol};
  }
  if (options.render_mode == "hybrid") {
    return RenderModeResolution{.mode = ResolvedRenderMode::Hybrid, .protocol = protocol};
  }
  return RenderModeResolution{};
}

std::string_view toString(ResolvedRenderMode mode) {
  switch (mode) {
    case ResolvedRenderMode::Text:
      return "text";
    case ResolvedRenderMode::Pixel:
      return "pixel";
    case ResolvedRenderMode::Hybrid:
      return "hybrid";
  }
  return "text";
}

std::string_view toString(GraphicsProtocol protocol) {
  switch (protocol) {
    case GraphicsProtocol::None:
      return "none";
    case GraphicsProtocol::Kitty:
      return "kitty";
    case GraphicsProtocol::Sixel:
      return "sixel";
    case GraphicsProtocol::ITermInline:
      return "iterm-inline";
  }
  return "none";
}

}  // namespace contourtty
