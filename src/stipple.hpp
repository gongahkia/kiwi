#pragma once

#include "cell_buffer.hpp"
#include "frame.hpp"

#include <cstdint>
#include <string_view>

namespace contourtty {

enum class StippleCarrier {
  Cell,
  Braille,
  Octant,
};

uint8_t blueNoiseRank64(int x, int y);
StippleCarrier stippleCarrierFromMode(std::string_view mode) noexcept;
char32_t stippleGlyphForLuminance(double luminance, uint8_t noise_rank);
void applyStipple(CellBuffer* cells, StippleCarrier carrier = StippleCarrier::Cell, const Frame* source_frame = nullptr);

}  // namespace contourtty
