#pragma once

#include "cli.hpp"
#include "renderer.hpp"
#include "terminal.hpp"

#include <memory>
#include <optional>

namespace strok {

RendererConfig rendererConfigFromCliOptions(const CliOptions& options);

class CliRendererSession {
 public:
  CliRendererSession() = default;
  CliRendererSession(const CliRendererSession&) = delete;
  CliRendererSession& operator=(const CliRendererSession&) = delete;
  CliRendererSession(CliRendererSession&&) = delete;
  CliRendererSession& operator=(CliRendererSession&&) = delete;

  RenderResult render(const Frame& frame, const Frame* lookahead, const CliOptions& options, TerminalSize terminal, CellBuffer* cells, RenderStats* stats = nullptr);
  RenderResult render(const RenderInput& input, const CliOptions& options, TerminalSize terminal, CellBuffer* cells, RenderStats* stats = nullptr);
  void reset();

 private:
  std::unique_ptr<Renderer> renderer_;
  std::optional<RendererConfig> config_;
  RenderGrid grid_;
};

// Player/frontend code owns source pacing and invokes this once per ordered source
// frame; the renderer itself uses fixed logical temporal steps.
void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats = nullptr, RenderTemporalState* temporal_state = nullptr);
void renderFrame(const Frame& frame, const Frame* lookahead, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats = nullptr, RenderTemporalState* temporal_state = nullptr);
void renderFrame(const RenderInput& input, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats = nullptr, RenderTemporalState* temporal_state = nullptr);
std::string dumpRenderGraph(const CliOptions& options);

}  // namespace strok
