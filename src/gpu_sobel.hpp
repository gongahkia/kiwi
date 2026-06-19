#pragma once

#include "glyph_shape.hpp"
#include "structure_edges.hpp"

#include <cstdint>
#include <optional>
#include <vector>

namespace contourtty {

struct GpuStructureGlyphs {
  std::vector<char32_t> glyphs;
  int64_t shape_match_cells = 0;
};

bool gpuSobelAvailable();
std::optional<GradientField> computeSobelGradientsGpu(const LuminanceField& field);
std::optional<GpuStructureGlyphs> computeStructureGlyphsGpu(const LuminanceField& field, int cols, int rows, double edge_threshold, const GlyphShapeTable* shape_table);

}  // namespace contourtty
