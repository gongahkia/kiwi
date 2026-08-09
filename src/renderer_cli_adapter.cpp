#include "renderer_cli_adapter.hpp"

#include <optional>
#include <utility>

namespace strok {
namespace {

void accumulate(RenderStats* total, const RenderStats& frame) {
  if (total == nullptr) {
    return;
  }
  total->frames += frame.frames;
  total->cells += frame.cells;
  total->render_ns += frame.render_ns;
  total->graph_topology_builds += frame.graph_topology_builds;
  total->graph_topology_reuses += frame.graph_topology_reuses;
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
  total->temporal_cell_candidate_cells += frame.temporal_cell_candidate_cells;
  total->temporal_cell_reused_cells += frame.temporal_cell_reused_cells;
  total->temporal_candidate_reconstruction_score += frame.temporal_candidate_reconstruction_score;
  total->temporal_candidate_temporal_score += frame.temporal_candidate_temporal_score;
  total->temporal_candidate_presentation_cost += frame.temporal_candidate_presentation_cost;
  total->modeled_symbolic_update_units += frame.modeled_symbolic_update_units;
  total->symbolic_update_budget_exceeded = total->symbolic_update_budget_exceeded || frame.symbolic_update_budget_exceeded;
  total->budget_suppressed_updates += frame.budget_suppressed_updates;
  total->budget_reconstruction_score_loss += frame.budget_reconstruction_score_loss;
  total->warp_history_cells += frame.warp_history_cells;
  total->warp_history_ns += frame.warp_history_ns;
  total->temporal_supersample_frames += frame.temporal_supersample_frames;
  total->temporal_supersample_ns += frame.temporal_supersample_ns;
}

bool sameConfig(const RendererConfig& left, const RendererConfig& right) {
  return left.width == right.width &&
         left.height == right.height &&
         left.cell_aspect == right.cell_aspect &&
         left.mode == right.mode &&
         left.style == right.style &&
         left.structure_overlay == right.structure_overlay &&
         left.font_path == right.font_path &&
         left.glyph_features == right.glyph_features &&
         left.ramp_sort == right.ramp_sort &&
         left.charset == right.charset &&
         left.edge_threshold == right.edge_threshold &&
         left.edge_strength == right.edge_strength &&
         left.dog_sigma == right.dog_sigma &&
         left.dog_sigma2 == right.dog_sigma2 &&
         left.dog_threshold == right.dog_threshold &&
         left.etf_iters == right.etf_iters &&
         left.lic_length == right.lic_length &&
         left.posterize == right.posterize &&
         left.contrast == right.contrast &&
         left.glyph_stickiness == right.glyph_stickiness &&
         left.orient_stickiness == right.orient_stickiness &&
         left.presentation_cost_weight == right.presentation_cost_weight &&
         left.symbolic_update_budget == right.symbolic_update_budget &&
         left.temporal_supersample == right.temporal_supersample &&
         left.temporal_cell_reuse == right.temporal_cell_reuse &&
         left.fit == right.fit &&
         left.gpu == right.gpu &&
         left.line_ligatures == right.line_ligatures &&
         left.collect_symbolic_metrics == right.collect_symbolic_metrics &&
         left.graph_passes == right.graph_passes;
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

RenderResult CliRendererSession::render(const Frame& frame,
                                        const Frame* lookahead,
                                        const CliOptions& options,
                                        TerminalSize terminal,
                                        CellBuffer* cells,
                                        RenderStats* stats) {
  const std::optional<ColorImageView> color = colorImageViewFromFrame(frame);
  std::optional<ColorImageView> lookahead_color;
  if (lookahead != nullptr) {
    lookahead_color = colorImageViewFromFrame(*lookahead).value_or(ColorImageView{});
  }
  return render(RenderInput{
                    .color = color.value_or(ColorImageView{}),
                    .lookahead_color = lookahead_color,
                  },
                options,
                terminal,
                cells,
                stats);
}

RenderResult CliRendererSession::render(const RenderInput& input,
                                        const CliOptions& options,
                                        TerminalSize terminal,
                                        CellBuffer* cells,
                                        RenderStats* stats) {
  const RendererConfig config = rendererConfigFromCliOptions(options);
  const RenderGrid grid{.cols = terminal.cols, .rows = terminal.rows};
  if (renderer_ == nullptr || !config_.has_value() || !sameConfig(*config_, config) ||
      grid_.cols != grid.cols || grid_.rows != grid.rows) {
    Renderer::CreateResult created = Renderer::create(config, grid);
    if (!created.succeeded()) {
      accumulate(stats, created.result.stats);
      return created.result;
    }
    renderer_ = std::move(created.renderer);
    config_ = config;
    grid_ = grid;
  }

  const RenderResult result = renderer_->render(input, cells);
  accumulate(stats, result.stats);
  return result;
}

void CliRendererSession::reset() {
  renderer_.reset();
  config_.reset();
  grid_ = {};
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
