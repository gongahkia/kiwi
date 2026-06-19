#include "renderer.hpp"

#include "braille_renderer.hpp"
#include "frame_sampling.hpp"
#include "glyph_ramp.hpp"
#include "gpu_sobel.hpp"
#include "halfblock_renderer.hpp"
#include "luminance.hpp"
#include "render_layout.hpp"
#include "structure_edges.hpp"
#include "structure_sampling.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
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

int renderWorkerCount(int cols, int rows) {
  if (rows < 2 || cols * rows < 1024) {
    return 1;
  }
  const unsigned hardware = std::thread::hardware_concurrency();
  const int max_workers = static_cast<int>(hardware == 0 ? 2 : hardware);
  return std::min(rows, max_workers);
}

}  // namespace

void renderFrame(const Frame& frame, std::u32string_view ramp, const CliOptions& options, TerminalSize terminal, const GlyphShapeTable* shape_table, CellBuffer* cells, RenderStats* stats) {
  const auto render_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
  const RenderSize size = fitRenderSize(frame, options, terminal);
  cells->resize(size.cols, size.rows);
  if (stats != nullptr) {
    ++stats->frames;
    stats->cells += static_cast<int64_t>(size.cols) * static_cast<int64_t>(size.rows);
  }
  if (options.mode == "halfblock") {
    renderHalfBlockFrame(frame, size.cols, size.rows, cells);
    if (stats != nullptr) {
      stats->render_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - render_started).count();
    }
    return;
  }
  if (options.charset.has_value() && isBrailleCharset(*options.charset)) {
    renderBrailleFrame(frame, size.cols, size.rows, cells);
    if (stats != nullptr) {
      stats->render_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - render_started).count();
    }
    return;
  }
  std::optional<GradientField> structure_gradients;
  std::optional<LuminanceField> structure_ink;
  const double edge_threshold = effectiveEdgeThresholdFromCli(options);
  if (options.mode == "structure") {
    LuminanceField analysis_luminance = makeLuminanceField(frame);
    analysis_luminance = applyStructureContrast(analysis_luminance, contrastFromCli(options));
    const DogOptions dog_options = dogOptionsFromCli(options);
    if (dog_options.enabled()) {
      analysis_luminance = differenceOfGaussians(analysis_luminance, dog_options);
    }
    if (options.gpu) {
      structure_gradients = computeSobelGradientsGpu(analysis_luminance);
    }
    if (!structure_gradients.has_value()) {
      structure_gradients = computeSobelGradients(analysis_luminance);
    }
    structure_ink = gradientMagnitudeField(*structure_gradients, edge_threshold);
  }
  std::vector<Cell>& cell_values = cells->cells();
  const int workers = renderWorkerCount(size.cols, size.rows);
  std::vector<ShapeMatchStats> worker_stats(static_cast<std::size_t>(workers));
  const auto render_rows = [&](int row_begin, int row_end, ShapeMatchStats* local_stats) {
    for (int row = row_begin; row < row_end; ++row) {
      for (int col = 0; col < size.cols; ++col) {
        const Rgb avg = averageRegion(frame, size.cols, size.rows, col, row);
        Cell& cell = cell_values[static_cast<std::size_t>(row) * static_cast<std::size_t>(size.cols) + static_cast<std::size_t>(col)];
        cell.glyph = glyphForLuminance(relativeLuminance(avg), ramp);
        if (structure_gradients.has_value()) {
          const CellGradient gradient = cellGradient(*structure_gradients, size.cols, size.rows, col, row);
          const std::optional<char32_t> edge_glyph = directionalGlyphForGradient(gradient, edge_threshold);
          if (edge_glyph.has_value()) {
            if (shape_table != nullptr && structure_ink.has_value()) {
              const auto match_started = stats != nullptr ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
              const CellLuminanceRegion region = sampleCellRegion(*structure_ink, size.cols, size.rows, col, row);
              cell.glyph = matchGlyphShape(shapeVectorForCell(region), *shape_table);
              if (stats != nullptr) {
                ++local_stats->cells;
                local_stats->ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - match_started).count();
              }
            } else {
              cell.glyph = *edge_glyph;
            }
          }
        }
        cell.fg = avg;
        cell.bg = Rgb{};
      }
    }
  };
  if (workers == 1) {
    render_rows(0, size.rows, &worker_stats[0]);
  } else {
    std::vector<std::thread> threads;
    threads.reserve(static_cast<std::size_t>(workers - 1));
    for (int worker = 1; worker < workers; ++worker) {
      const int row_begin = (size.rows * worker) / workers;
      const int row_end = (size.rows * (worker + 1)) / workers;
      threads.emplace_back(render_rows, row_begin, row_end, &worker_stats[static_cast<std::size_t>(worker)]);
    }
    render_rows(0, size.rows / workers, &worker_stats[0]);
    for (std::thread& thread : threads) {
      thread.join();
    }
  }
  if (stats != nullptr) {
    for (const ShapeMatchStats& local_stats : worker_stats) {
      stats->shape_match_cells += local_stats.cells;
      stats->shape_match_ns += local_stats.ns;
    }
    stats->render_ns += std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - render_started).count();
  }
}

}  // namespace contourtty
