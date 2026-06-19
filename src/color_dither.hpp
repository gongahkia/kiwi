#pragma once

#include "cell_buffer.hpp"
#include "color_mode.hpp"
#include "color_quantization.hpp"

namespace contourtty {

bool supportsPaletteDither(ColorMode mode) noexcept;
CellBuffer applyPaletteDither(const CellBuffer& input, ColorMode mode, DitherMode dither_mode);
CellBuffer applyFloydSteinbergDither(const CellBuffer& input, ColorMode mode);

}  // namespace contourtty
