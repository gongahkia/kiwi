#include "renderer.hpp"

#include "block_sad.hpp"
#include "braille_renderer.hpp"
#include "crosshatch.hpp"
#include "etf.hpp"
#include "frame_sampling.hpp"
#include "glyph_hog.hpp"
#include "glyph_ramp.hpp"
#include "glyph_sdf.hpp"
#include "gpu_sobel.hpp"
#include "halfblock_renderer.hpp"
#include "kuwahara.hpp"
#include "line_ligatures.hpp"
#include "luminance.hpp"
#include "octant_renderer.hpp"
#include "render_graph.hpp"
#include "render_layout.hpp"
#include "sextant_renderer.hpp"
#include "stipple.hpp"
#include "structure_edges.hpp"
#include "structure_overlay.hpp"
#include "structure_sampling.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace contourtty {
namespace {

constexpr double kDefaultDogThreshold = 0.02;
constexpr double kDefaultEdgeThreshold = 0.35;
constexpr double kDefaultEdgeStrength = 1.0;

struct ShapeMatchStats {
  int64_t cells = 0;
  int64_t ns = 0;
};

PassPort renderPort(std::string name, BufferKind kind) {
  return PassPort{
    .name = std::move(name),
    .desc = BufferDesc{.kind = kind},
  };
}

DogOptions dogOptionsFromCli(const CliOptions& options) {
  const double sigma1 = options.dog_sigma.value_or(0.0);
  return DogOptions{
    .sigma1 = sigma1,
    .sigma2 = options.dog_sigma2.value_or(sigma1 > 0.0 ? sigma1 * 2.0 : 0.0),
    .threshold = options.dog_threshold.value_or(kDefaultDogThreshold),
  };
}

double contrastFromCli(const CliOptions& options) {
  return options.contrast.value_or(0.0);
}

double edgeThresholdFromCli(const CliOptions& options) {
  return options.edge_threshold.value_or(kDefaultEdgeThreshold);
}

double effectiveEdgeThresholdFromCli(const CliOptions& options) {
  const double strength = options.edge_strength.value_or(kDefaultEdgeStrength);
  if (strength <= 0.0) {
    return std::numeric_limits<double>::infinity();
  }
  return edgeThresholdFromCli(options) / strength;
}

int etfIterationsFromCli(const CliOptions& options) {
  return options.etf_iters.value_or(options.style == "hatch" ? 2 : 0);
}

bool painterlyStyleEnabled(const CliOptions& options) {
  return options.style == "painterly";
}

bool hatchStyleEnabled(const CliOptions& options) {
  return options.style == "hatch";
}

bool stippleStyleEnabled(const CliOptions& options) {
  return options.style == "stipple";
}

int renderWorkerCount(int cols, int rows) {
  if (rows < 2 || cols * rows < 1024) {
    return 1;
  }
  const unsigned hardware = std::thread::hardware_concurrency();
  const int max_workers = static_cast<int>(hardware == 0 ? 2 : hardware);
  return std::min(rows, max_workers);
}

GraphBuildOptions renderGraphBuildOptions(const CliOptions& options) {
  GraphBuildOptions graph_options;
  graph_options.backend_preference = options.gpu
                                       ? std::vector<Backend>{Backend::Metal, Backend::Cpu}
                                       : std::vector<Backend>{Backend::Cpu};
  graph_options.available_backends = {Backend::Cpu};
  if (gpuSobelAvailable()) {
    graph_options.available_backends.push_back(Backend::Metal);
  }
  return graph_options;
}

std::optional<std::string> directBlitterMode(const CliOptions& options) {
  if (options.mode == "halfblock" || options.mode == "blocks" || options.mode == "octant" || options.mode == "sextant" || options.mode == "braille") {
    return options.mode;
  }
  if (options.charset.has_value() && isBrailleCharset(*options.charset)) {
    return "braille";
  }
  return std::nullopt;
}

std::vector<Pass> renderGraphSkeleton(const CliOptions& options) {
  const bool overlay_enabled = structureOverlayEnabled(options);
  const bool etf_enabled = etfIterationsFromCli(options) > 0;
  const bool painterly_enabled = painterlyStyleEnabled(options);
  const bool hatch_enabled = hatchStyleEnabled(options);
  const bool stipple_enabled = stippleStyleEnabled(options);
  const std::string frame_input = painterly_enabled ? "styled-frame" : "frame";
  const auto decode_pass = [] {
    return Pass{
      .id = "decode",
      .outputs = {renderPort("frame", BufferKind::RgbFrame)},
      .supports = {Backend::Cpu},
    };
  };
  const auto emit_pass = [](std::string input) {
    return Pass{
      .id = "emit",
      .inputs = {renderPort(std::move(input), BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    };
  };
  const auto luminance_pass = [&] {
    return Pass{
      .id = "luminance",
      .inputs = {renderPort(frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort("luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu},
    };
  };
  const auto append_structure_analysis = [&](std::vector<Pass>* passes) {
    const std::string sobel_output = etf_enabled ? "raw-gradients" : "gradients";
    passes->push_back(Pass{
      .id = "contrast",
      .inputs = {renderPort("luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort("contrast-luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu},
    });
    passes->push_back(Pass{
      .id = "dog",
      .inputs = {renderPort("contrast-luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort("structure-luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu, Backend::Metal},
    });
    passes->push_back(Pass{
      .id = "sobel",
      .inputs = {renderPort("structure-luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort(sobel_output, BufferKind::GradientField)},
      .supports = {Backend::Cpu, Backend::Metal},
    });
    if (etf_enabled) {
      passes->push_back(Pass{
        .id = "etf",
        .inputs = {renderPort("raw-gradients", BufferKind::GradientField)},
        .outputs = {renderPort("gradients", BufferKind::GradientField)},
        .supports = {Backend::Cpu},
      });
    }
    passes->push_back(Pass{
      .id = "edge-field",
      .inputs = {renderPort("gradients", BufferKind::GradientField)},
      .outputs = {renderPort("edge-field", BufferKind::EdgeField)},
      .supports = {Backend::Cpu},
    });
  };
  const auto append_structure_overlay = [&](std::vector<Pass>* passes, const std::string& base_input) {
    if (hatch_enabled) {
      passes->push_back(Pass{
        .id = "crosshatch",
        .inputs = {renderPort("gradients", BufferKind::GradientField), renderPort(base_input, BufferKind::CellGlyphs)},
        .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
        .supports = {Backend::Cpu},
      });
      return;
    }
    passes->push_back(Pass{
      .id = "cell-shape",
      .inputs = {renderPort("edge-field", BufferKind::EdgeField), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cell-shapes", BufferKind::CellShapeVectors)},
      .supports = {Backend::Cpu},
    });
    passes->push_back(Pass{
      .id = "overlay-structure",
      .inputs = {renderPort("edge-field", BufferKind::EdgeField), renderPort("cell-shapes", BufferKind::CellShapeVectors), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu, Backend::Metal},
    });
  };
  const auto append_line_ligatures = [&](std::vector<Pass>* passes) {
    if (!options.line_ligatures || !overlay_enabled) {
      return std::string("cells");
    }
    passes->push_back(Pass{
      .id = "line-ligatures",
      .inputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .outputs = {renderPort("ligature-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    return std::string("ligature-cells");
  };
  const auto append_stipple = [&](std::vector<Pass>* passes, const std::string& input) {
    if (!stipple_enabled) {
      return input;
    }
    passes->push_back(Pass{
      .id = "stipple",
      .inputs = {renderPort(input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("stipple-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    return std::string("stipple-cells");
  };
  const auto emit_styled = [&](std::vector<Pass>* passes, const std::string& input) {
    passes->push_back(emit_pass(append_stipple(passes, input)));
  };
  std::vector<Pass> passes;
  passes.push_back(decode_pass());
  if (painterly_enabled) {
    passes.push_back(Pass{
      .id = "kuwahara",
      .inputs = {renderPort("frame", BufferKind::RgbFrame)},
      .outputs = {renderPort("styled-frame", BufferKind::RgbFrame)},
      .supports = {Backend::Cpu},
    });
  }
  if (const std::optional<std::string> blitter = directBlitterMode(options)) {
    const std::string blitter_output = overlay_enabled ? "base-cells" : "cells";
    passes.push_back(Pass{
      .id = *blitter,
      .inputs = {renderPort(frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort(blitter_output, BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    if (overlay_enabled) {
      passes.push_back(luminance_pass());
      append_structure_analysis(&passes);
      append_structure_overlay(&passes, blitter_output);
    }
    emit_styled(&passes, append_line_ligatures(&passes));
    return passes;
  }
  passes.push_back(luminance_pass());
  if (overlay_enabled) {
    append_structure_analysis(&passes);
    passes.push_back(Pass{
      .id = "cell-average",
      .inputs = {renderPort(frame_input, BufferKind::RgbFrame), renderPort("gradients", BufferKind::GradientField)},
      .outputs = {renderPort("cell-colors", BufferKind::CellColors)},
      .supports = {Backend::Cpu, Backend::Metal},
    });
    passes.push_back(Pass{
      .id = "ramp-pick",
      .inputs = {renderPort("cell-colors", BufferKind::CellColors), renderPort("luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort("base-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    });
    append_structure_overlay(&passes, "base-cells");
    emit_styled(&passes, append_line_ligatures(&passes));
    return passes;
  }
  passes.push_back(Pass{
    .id = "cell-average",
    .inputs = {renderPort(frame_input, BufferKind::RgbFrame)},
    .outputs = {renderPort("cell-colors", BufferKind::CellColors)},
    .supports = {Backend::Cpu, Backend::Metal},
  });
  passes.push_back(Pass{
    .id = "ramp-pick",
    .inputs = {renderPort("cell-colors", BufferKind::CellColors), renderPort("luminance", BufferKind::LuminanceField)},
    .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
    .supports = {Backend::Cpu},
  });
  emit_styled(&passes, "cells");
  return passes;
}

}  // namespace

std::string dumpRenderGraph(const CliOptions& options) {
  return buildGraph(renderGraphSkeleton(options), renderGraphBuildOptions(options)).dump();
}

void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats) {
  const auto render_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
  const RenderSize size = fitRenderSize(frame, options, terminal);
  cells->resize(size.cols, size.rows);
  if (stats != nullptr) {
    ++stats->frames;
    stats->cells += static_cast<int64_t>(size.cols) * static_cast<int64_t>(size.rows);
  }

  std::optional<LuminanceField> analysis_luminance;
  std::optional<GradientField> structure_gradients;
  std::optional<LuminanceField> structure_ink;
  std::optional<GpuStructureGlyphs> gpu_structure_glyphs;
  std::vector<Rgb> average_colors;
  std::vector<CellLuminanceRegion> cell_shape_regions;
  const double edge_threshold = effectiveEdgeThresholdFromCli(options);
  const bool overlay_enabled = structureOverlayEnabled(options);
  const bool etf_enabled = etfIterationsFromCli(options) > 0;
  const bool painterly_enabled = painterlyStyleEnabled(options);
  const bool hatch_enabled = hatchStyleEnabled(options);
  const bool stipple_enabled = stippleStyleEnabled(options);
  const std::string frame_input = painterly_enabled ? "styled-frame" : "frame";
  Frame styled_frame;
  const Frame* render_frame = &frame;
  const auto active_frame = [&]() -> const Frame& {
    return *render_frame;
  };
  std::vector<ShapeMatchStats> worker_stats;

  const auto finish_stats = [&] {
    if (stats != nullptr) {
      for (const ShapeMatchStats& local_stats : worker_stats) {
        stats->shape_match_cells += local_stats.cells;
        stats->shape_match_ns += local_stats.ns;
      }
      stats->render_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - render_started).count();
    }
  };

  const auto run_graph = [&](std::vector<Pass> passes) {
    Graph graph = buildGraph(std::move(passes), renderGraphBuildOptions(options));
    PassContext context;
    graph.run(context);
  };

  const auto decode_pass = [&] {
    return Pass{
      .id = "decode",
      .outputs = {renderPort("frame", BufferKind::RgbFrame)},
      .supports = {Backend::Cpu},
    };
  };

  const auto kuwahara_pass = [&] {
    return Pass{
      .id = "kuwahara",
      .inputs = {renderPort("frame", BufferKind::RgbFrame)},
      .outputs = {renderPort("styled-frame", BufferKind::RgbFrame)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        styled_frame = applyKuwaharaFilter(frame, 2);
        render_frame = &styled_frame;
      },
    };
  };

  const auto emit_pass = [&](std::string input) {
    return Pass{
      .id = "emit",
      .inputs = {renderPort(std::move(input), BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
    };
  };

  const auto luminance_pass = [&] {
    return Pass{
      .id = "luminance",
      .inputs = {renderPort(frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort("luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        analysis_luminance = makeLuminanceField(active_frame());
      },
    };
  };

  const auto append_blitter_pass = [&](std::vector<Pass>* passes, const std::string& blitter, const std::string& output) {
    passes->push_back(Pass{
      .id = blitter,
      .inputs = {renderPort(frame_input, BufferKind::RgbFrame)},
      .outputs = {renderPort(output, BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&, blitter](PassContext&) {
        if (blitter == "halfblock") {
          renderHalfBlockFrame(active_frame(), size.cols, size.rows, cells);
        } else if (blitter == "blocks") {
          renderBlockSadFrame(active_frame(), size.cols, size.rows, cells);
        } else if (blitter == "octant") {
          renderOctantFrame(active_frame(), size.cols, size.rows, cells);
        } else if (blitter == "sextant") {
          renderSextantFrame(active_frame(), size.cols, size.rows, cells);
        } else if (blitter == "braille") {
          renderBrailleFrame(active_frame(), size.cols, size.rows, cells);
        }
      },
    });
  };

  const auto cell_average_pass = [&](std::vector<PassPort> inputs) {
    return Pass{
      .id = "cell-average",
      .inputs = std::move(inputs),
      .outputs = {renderPort("cell-colors", BufferKind::CellColors)},
      .supports = {Backend::Cpu, Backend::Metal},
      .run = [&](PassContext&) {
        const std::vector<Cell>& cell_values = cells->cells();
        average_colors.assign(cell_values.size(), Rgb{});
        const bool has_gpu_average = gpu_structure_glyphs.has_value() && gpu_structure_glyphs->average_colors.size() == cell_values.size();
        const int workers = renderWorkerCount(size.cols, size.rows);
        const auto fill_rows = [&](int row_begin, int row_end) {
          for (int row = row_begin; row < row_end; ++row) {
            for (int col = 0; col < size.cols; ++col) {
              const std::size_t cell_index = static_cast<std::size_t>(row) * static_cast<std::size_t>(size.cols) + static_cast<std::size_t>(col);
              average_colors[cell_index] = has_gpu_average ? gpu_structure_glyphs->average_colors[cell_index] : averageRegion(active_frame(), size.cols, size.rows, col, row);
            }
          }
        };
        if (workers == 1) {
          fill_rows(0, size.rows);
        } else {
          std::vector<std::thread> threads;
          threads.reserve(static_cast<std::size_t>(workers - 1));
          for (int worker = 1; worker < workers; ++worker) {
            const int row_begin = (size.rows * worker) / workers;
            const int row_end = (size.rows * (worker + 1)) / workers;
            threads.emplace_back(fill_rows, row_begin, row_end);
          }
          fill_rows(0, size.rows / workers);
          for (std::thread& thread : threads) {
            thread.join();
          }
        }
      },
    };
  };

  const auto ramp_pick_pass = [&](std::string output) {
    return Pass{
      .id = "ramp-pick",
      .inputs = {renderPort("cell-colors", BufferKind::CellColors), renderPort("luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort(std::move(output), BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        std::vector<Cell>& cell_values = cells->cells();
        for (std::size_t index = 0; index < cell_values.size(); ++index) {
          const Rgb avg = average_colors[index];
          Cell& cell = cell_values[index];
          cell.glyph = glyphForLuminance(relativeLuminance(avg), ramp);
          cell.fg = avg;
          cell.bg = Rgb{};
        }
      },
    };
  };

  const auto append_structure_analysis = [&](std::vector<Pass>* passes) {
    passes->push_back(Pass{
      .id = "contrast",
      .inputs = {renderPort("luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort("contrast-luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        analysis_luminance = applyStructureContrast(*analysis_luminance, contrastFromCli(options));
      },
    });
    passes->push_back(Pass{
      .id = "dog",
      .inputs = {renderPort("contrast-luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort("structure-luminance", BufferKind::LuminanceField)},
      .supports = {Backend::Cpu, Backend::Metal},
      .run = [&](PassContext& context) {
        const DogOptions dog_options = dogOptionsFromCli(options);
        if (!dog_options.enabled()) {
          return;
        }
        if (context.backend() == Backend::Metal) {
          if (auto gpu_dog = differenceOfGaussiansGpu(*analysis_luminance, dog_options)) {
            analysis_luminance = std::move(*gpu_dog);
            return;
          }
        }
        analysis_luminance = differenceOfGaussians(*analysis_luminance, dog_options);
      },
    });
    passes->push_back(Pass{
      .id = "sobel",
      .inputs = {renderPort("structure-luminance", BufferKind::LuminanceField)},
      .outputs = {renderPort(etf_enabled ? "raw-gradients" : "gradients", BufferKind::GradientField)},
      .supports = {Backend::Cpu, Backend::Metal},
      .run = [&](PassContext& context) {
        if (!etf_enabled && context.backend() == Backend::Metal && (shape_table == nullptr || shape_table->feature_kind == GlyphFeatureKind::Overlap)) {
          gpu_structure_glyphs = computeStructureGlyphsGpu(active_frame(), *analysis_luminance, size.cols, size.rows, edge_threshold, shape_table);
          if (gpu_structure_glyphs.has_value()) {
            if (stats != nullptr) {
              stats->shape_match_cells += gpu_structure_glyphs->shape_match_cells;
            }
            return;
          }
          structure_gradients = computeSobelGradientsGpu(*analysis_luminance);
        }
        if (!structure_gradients.has_value()) {
          structure_gradients = computeSobelGradients(*analysis_luminance);
        }
      },
    });
    if (etf_enabled) {
      passes->push_back(Pass{
        .id = "etf",
        .inputs = {renderPort("raw-gradients", BufferKind::GradientField)},
        .outputs = {renderPort("gradients", BufferKind::GradientField)},
        .supports = {Backend::Cpu},
        .run = [&](PassContext&) {
          if (structure_gradients.has_value()) {
            structure_gradients = smoothEtfGradients(*structure_gradients, etfIterationsFromCli(options));
          }
        },
      });
    }
    passes->push_back(Pass{
      .id = "edge-field",
      .inputs = {renderPort("gradients", BufferKind::GradientField)},
      .outputs = {renderPort("edge-field", BufferKind::EdgeField)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        if (structure_gradients.has_value()) {
          structure_ink = etf_enabled
                            ? coherentLineField(*structure_gradients, edge_threshold)
                            : gradientMagnitudeField(*structure_gradients, edge_threshold);
        }
      },
    });
  };

  const auto cell_shape_pass = [&](const std::string& base_input) {
    return Pass{
      .id = "cell-shape",
      .inputs = {renderPort("edge-field", BufferKind::EdgeField), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cell-shapes", BufferKind::CellShapeVectors)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        cell_shape_regions.clear();
        if (shape_table == nullptr || !structure_ink.has_value()) {
          return;
        }
        cell_shape_regions.reserve(cells->cells().size());
        for (int row = 0; row < size.rows; ++row) {
          for (int col = 0; col < size.cols; ++col) {
            cell_shape_regions.push_back(sampleCellRegion(*structure_ink, size.cols, size.rows, col, row));
          }
        }
      },
    };
  };

  const auto overlay_structure_pass = [&](const std::string& base_input) {
    return Pass{
      .id = "overlay-structure",
      .inputs = {renderPort("edge-field", BufferKind::EdgeField), renderPort("cell-shapes", BufferKind::CellShapeVectors), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu, Backend::Metal},
      .run = [&](PassContext&) {
        std::vector<Cell>& cell_values = cells->cells();
        if (gpu_structure_glyphs.has_value() && (shape_table == nullptr || shape_table->feature_kind == GlyphFeatureKind::Overlap)) {
          for (std::size_t index = 0; index < cell_values.size(); ++index) {
            const char32_t gpu_glyph = gpu_structure_glyphs->glyphs[index];
            if (gpu_glyph != U'\0') {
              cell_values[index].glyph = gpu_glyph;
            }
          }
          return;
        }
        if (!structure_gradients.has_value()) {
          return;
        }
        const int workers = renderWorkerCount(size.cols, size.rows);
        worker_stats.assign(static_cast<std::size_t>(workers), ShapeMatchStats{});
        const auto match_rows = [&](int row_begin, int row_end, ShapeMatchStats* local_stats) {
          for (int row = row_begin; row < row_end; ++row) {
            for (int col = 0; col < size.cols; ++col) {
              const std::size_t cell_index = static_cast<std::size_t>(row) * static_cast<std::size_t>(size.cols) + static_cast<std::size_t>(col);
              Cell& cell = cell_values[cell_index];
              const CellGradient gradient = cellGradient(*structure_gradients, size.cols, size.rows, col, row);
              const std::optional<char32_t> edge_glyph = directionalGlyphForGradient(gradient, edge_threshold);
              if (!edge_glyph.has_value()) {
                continue;
              }
              if (shape_table != nullptr && structure_ink.has_value()) {
                const auto match_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
                const auto match_region = [&](const CellLuminanceRegion& region) {
                  if (shape_table->feature_count == kHogFeatureCount) {
                    return hogVectorForCell(region);
                  }
                  if (shape_table->feature_kind == GlyphFeatureKind::Sdf) {
                    return sdfVectorForCell(region);
                  }
                  return shapeVectorForCell(region);
                };
                if (cell_shape_regions.empty()) {
                  const CellLuminanceRegion region = sampleCellRegion(*structure_ink, size.cols, size.rows, col, row);
                  cell.glyph = matchGlyphShape(match_region(region), *shape_table);
                } else {
                  cell.glyph = matchGlyphShape(match_region(cell_shape_regions[cell_index]), *shape_table);
                }
                if (stats != nullptr) {
                  ++local_stats->cells;
                  local_stats->ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - match_started).count();
                }
              } else {
                cell.glyph = *edge_glyph;
              }
            }
          }
        };
        if (workers == 1) {
          match_rows(0, size.rows, &worker_stats[0]);
        } else {
          std::vector<std::thread> threads;
          threads.reserve(static_cast<std::size_t>(workers - 1));
          for (int worker = 1; worker < workers; ++worker) {
            const int row_begin = (size.rows * worker) / workers;
            const int row_end = (size.rows * (worker + 1)) / workers;
            threads.emplace_back(match_rows, row_begin, row_end, &worker_stats[static_cast<std::size_t>(worker)]);
          }
          match_rows(0, size.rows / workers, &worker_stats[0]);
          for (std::thread& thread : threads) {
            thread.join();
          }
        }
      },
    };
  };

  const auto crosshatch_pass = [&](const std::string& base_input) {
    return Pass{
      .id = "crosshatch",
      .inputs = {renderPort("gradients", BufferKind::GradientField), renderPort(base_input, BufferKind::CellGlyphs)},
      .outputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        if (structure_gradients.has_value()) {
          applyCrosshatch(cells, *structure_gradients, size.cols, size.rows, edge_threshold);
        }
      },
    };
  };

  const auto line_ligatures_pass = [&] {
    return Pass{
      .id = "line-ligatures",
      .inputs = {renderPort("cells", BufferKind::CellGlyphs)},
      .outputs = {renderPort("ligature-cells", BufferKind::CellGlyphs)},
      .supports = {Backend::Cpu},
      .run = [&](PassContext&) {
        applyLineLigatures(cells);
      },
    };
  };

  const auto append_emit_after_overlay = [&](std::vector<Pass>* passes) {
    const auto append_stipple_pass = [&](std::string input) {
      if (!stipple_enabled) {
        return input;
      }
      passes->push_back(Pass{
        .id = "stipple",
        .inputs = {renderPort(input, BufferKind::CellGlyphs)},
        .outputs = {renderPort("stipple-cells", BufferKind::CellGlyphs)},
        .supports = {Backend::Cpu},
        .run = [&](PassContext&) {
          applyStipple(cells);
        },
      });
      return std::string("stipple-cells");
    };
    std::string output = "cells";
    if (options.line_ligatures && overlay_enabled) {
      passes->push_back(line_ligatures_pass());
      output = "ligature-cells";
    }
    passes->push_back(emit_pass(append_stipple_pass(output)));
  };

  if (const std::optional<std::string> blitter = directBlitterMode(options)) {
    std::vector<Pass> passes;
    const std::string blitter_output = overlay_enabled ? "base-cells" : "cells";
    passes.push_back(decode_pass());
    if (painterly_enabled) {
      passes.push_back(kuwahara_pass());
    }
    append_blitter_pass(&passes, *blitter, blitter_output);
    if (overlay_enabled) {
      passes.push_back(luminance_pass());
      append_structure_analysis(&passes);
      if (hatch_enabled) {
        passes.push_back(crosshatch_pass(blitter_output));
      } else {
        passes.push_back(cell_shape_pass(blitter_output));
        passes.push_back(overlay_structure_pass(blitter_output));
      }
      append_emit_after_overlay(&passes);
    } else {
      append_emit_after_overlay(&passes);
    }
    run_graph(std::move(passes));
    finish_stats();
    return;
  }

  std::vector<Pass> passes;
  passes.push_back(decode_pass());
  if (painterly_enabled) {
    passes.push_back(kuwahara_pass());
  }
  passes.push_back(luminance_pass());

  if (overlay_enabled) {
    append_structure_analysis(&passes);
    passes.push_back(cell_average_pass({renderPort(frame_input, BufferKind::RgbFrame), renderPort("gradients", BufferKind::GradientField)}));
    passes.push_back(ramp_pick_pass("base-cells"));
    if (hatch_enabled) {
      passes.push_back(crosshatch_pass("base-cells"));
    } else {
      passes.push_back(cell_shape_pass("base-cells"));
      passes.push_back(overlay_structure_pass("base-cells"));
    }
    append_emit_after_overlay(&passes);
  } else {
    passes.push_back(cell_average_pass({renderPort(frame_input, BufferKind::RgbFrame)}));
    passes.push_back(ramp_pick_pass("cells"));
    append_emit_after_overlay(&passes);
  }

  run_graph(std::move(passes));
  finish_stats();
}

}  // namespace contourtty
