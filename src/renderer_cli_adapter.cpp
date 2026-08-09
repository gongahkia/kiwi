#include "renderer_cli_adapter.hpp"

#include <optional>

namespace strok {
namespace {

void accumulate(RenderStats* total, const RenderStats& frame) {
  if (total == nullptr) {
    return;
  }
  total->frames += frame.frames;
  total->cells += frame.cells;
  total->render_ns += frame.render_ns;
  total->changed_glyphs += frame.changed_glyphs;
  total->changed_foregrounds += frame.changed_foregrounds;
  total->changed_backgrounds += frame.changed_backgrounds;
  total->changed_cells += frame.changed_cells;
  total->shape_match_cells += frame.shape_match_cells;
  total->shape_match_ns += frame.shape_match_ns;
  total->optical_flow_blocks += frame.optical_flow_blocks;
  total->optical_flow_ns += frame.optical_flow_ns;
  total->external_motion_cells += frame.external_motion_cells;
  total->inferred_motion_cells += frame.inferred_motion_cells;
  total->history_suppressed_cells += frame.history_suppressed_cells;
  total->warp_history_cells += frame.warp_history_cells;
  total->warp_history_ns += frame.warp_history_ns;
  total->temporal_supersample_frames += frame.temporal_supersample_frames;
  total->temporal_supersample_ns += frame.temporal_supersample_ns;
}

}  // namespace

RendererConfig rendererConfigFromCliOptions(const CliOptions& options) {
  return RendererConfig{
    .width = options.width,
    .height = options.height,
    .cell_aspect = options.cell_aspect,
    .mode = options.mode,
    .style = options.style,
    .structure_overlay = options.structure_overlay,
    .font_path = options.font_path,
    .glyph_features = options.glyph_features,
    .ramp_sort = options.ramp_sort,
    .charset = options.charset,
    .edge_threshold = options.edge_threshold,
    .edge_strength = options.edge_strength,
    .dog_sigma = options.dog_sigma,
    .dog_sigma2 = options.dog_sigma2,
    .dog_threshold = options.dog_threshold,
    .etf_iters = options.etf_iters,
    .lic_length = options.lic_length,
    .posterize = options.posterize,
    .contrast = options.contrast,
    .glyph_stickiness = options.glyph_stickiness,
    .orient_stickiness = options.orient_stickiness,
    .temporal_supersample = options.temporal_supersample,
    .fit = options.fit,
    .gpu = options.gpu,
    .line_ligatures = options.line_ligatures,
    .graph_passes = options.graph_passes,
  };
}

void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats, RenderTemporalState* temporal_state) {
  renderFrame(frame, nullptr, ramp, options, terminal, shape_table, cells, stats, temporal_state);
}

void renderFrame(const Frame& frame, const Frame* lookahead, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats, RenderTemporalState* temporal_state) {
  const std::optional<ColorImageView> color = colorImageViewFromFrame(frame);
  std::optional<ColorImageView> lookahead_color;
  if (lookahead != nullptr) {
    lookahead_color = colorImageViewFromFrame(*lookahead).value_or(ColorImageView{});
  }
  const RenderInput input{
    .color = color.value_or(ColorImageView{}),
    .lookahead_color = lookahead_color,
  };
  const RenderResult result = renderFrame(input, ramp, rendererConfigFromCliOptions(options), RenderGrid{.cols = terminal.cols, .rows = terminal.rows}, shape_table, cells, temporal_state);
  accumulate(stats, result.stats);
}

void renderFrame(const RenderInput& input, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats, RenderTemporalState* temporal_state) {
  const RenderResult result = renderFrame(input, ramp, rendererConfigFromCliOptions(options), RenderGrid{.cols = terminal.cols, .rows = terminal.rows}, shape_table, cells, temporal_state);
  accumulate(stats, result.stats);
}

std::string dumpRenderGraph(const CliOptions& options) {
  return dumpRenderGraph(rendererConfigFromCliOptions(options));
}

}  // namespace strok
