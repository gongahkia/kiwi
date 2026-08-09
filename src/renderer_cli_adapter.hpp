#pragma once

#include "cli.hpp"
#include "renderer.hpp"
#include "terminal.hpp"

namespace strok {

RendererConfig rendererConfigFromCliOptions(const CliOptions& options);
// Player/frontend code owns source pacing and invokes this once per ordered source
// frame; the renderer itself uses fixed logical temporal steps.
void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats = nullptr, RenderTemporalState* temporal_state = nullptr);
void renderFrame(const RenderInput& input, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats = nullptr, RenderTemporalState* temporal_state = nullptr);
std::string dumpRenderGraph(const CliOptions& options);

}  // namespace strok
