#include "line_ligatures.hpp"

#include <cstdint>
#include <optional>

namespace strok {
namespace {

constexpr uint8_t kUp = 0x01;
constexpr uint8_t kDown = 0x02;
constexpr uint8_t kLeft = 0x04;
constexpr uint8_t kRight = 0x08;

uint8_t opposite(uint8_t direction) {
  switch (direction) {
    case kUp:
      return kDown;
    case kDown:
      return kUp;
    case kLeft:
      return kRight;
    case kRight:
      return kLeft;
    default:
      return 0;
  }
}

uint8_t supportMask(char32_t glyph) {
  switch (glyph) {
    case U'|':
    case U'│':
      return kUp | kDown;
    case U'-':
    case U'_':
    case U'─':
      return kLeft | kRight;
    case U'/':
    case U'\\':
    case U'+':
    case U'┼':
      return kUp | kDown | kLeft | kRight;
    case U'┌':
      return kDown | kRight;
    case U'┐':
      return kDown | kLeft;
    case U'└':
      return kUp | kRight;
    case U'┘':
      return kUp | kLeft;
    case U'├':
      return kUp | kDown | kRight;
    case U'┤':
      return kUp | kDown | kLeft;
    case U'┬':
      return kLeft | kRight | kDown;
    case U'┴':
      return kLeft | kRight | kUp;
    default:
      return 0;
  }
}

std::optional<char32_t> glyphForMask(uint8_t mask) {
  switch (mask) {
    case kUp:
    case kDown:
    case kUp | kDown:
      return U'│';
    case kLeft:
    case kRight:
    case kLeft | kRight:
      return U'─';
    case kDown | kRight:
      return U'┌';
    case kDown | kLeft:
      return U'┐';
    case kUp | kRight:
      return U'└';
    case kUp | kLeft:
      return U'┘';
    case kUp | kDown | kRight:
      return U'├';
    case kUp | kDown | kLeft:
      return U'┤';
    case kLeft | kRight | kDown:
      return U'┬';
    case kLeft | kRight | kUp:
      return U'┴';
    case kUp | kDown | kLeft | kRight:
      return U'┼';
    default:
      return std::nullopt;
  }
}

uint8_t connectionMask(const CellBuffer& cells, int col, int row) {
  const uint8_t current_support = supportMask(cells.at(col, row).glyph);
  if (current_support == 0) {
    return 0;
  }

  uint8_t mask = 0;
  const auto connect = [&](uint8_t direction, int neighbor_col, int neighbor_row) {
    if (neighbor_col < 0 || neighbor_row < 0 || neighbor_col >= cells.cols() || neighbor_row >= cells.rows()) {
      return;
    }
    if ((current_support & direction) == 0) {
      return;
    }
    const uint8_t neighbor_support = supportMask(cells.at(neighbor_col, neighbor_row).glyph);
    if ((neighbor_support & opposite(direction)) != 0) {
      mask |= direction;
    }
  };
  connect(kUp, col, row - 1);
  connect(kDown, col, row + 1);
  connect(kLeft, col - 1, row);
  connect(kRight, col + 1, row);
  return mask;
}

}  // namespace

void applyLineLigatures(CellBuffer* cells) {
  const CellBuffer source = *cells;
  for (int row = 0; row < source.rows(); ++row) {
    for (int col = 0; col < source.cols(); ++col) {
      const std::optional<char32_t> glyph = glyphForMask(connectionMask(source, col, row));
      if (glyph.has_value()) {
        cells->at(col, row).glyph = *glyph;
      }
    }
  }
}

}  // namespace strok
