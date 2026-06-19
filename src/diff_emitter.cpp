#include "diff_emitter.hpp"

#include "ansi.hpp"

#include <optional>

namespace contourtty {
namespace {

bool sameColor(Rgb lhs, Rgb rhs) noexcept {
  return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b;
}

bool sameCell(const Cell& lhs, const Cell& rhs, bool mono) noexcept {
  if (mono) {
    return lhs.glyph == rhs.glyph;
  }
  return lhs.glyph == rhs.glyph && sameColor(lhs.fg, rhs.fg) && sameColor(lhs.bg, rhs.bg);
}

}  // namespace

EmissionResult DiffEmitter::emit(const CellBuffer& current, EmissionOptions options) {
  const bool full_repaint = !has_previous_ || previous_.cols() != current.cols() || previous_.rows() != current.rows();
  const bool truecolor = emitsTruecolor(options.color_mode);
  const bool mono = !truecolor;
  EmissionResult result;
  result.bytes.reserve(current.size() * 32);
  if (full_repaint && has_previous_) {
    result.bytes += "\x1b[2J";
  }

  std::optional<Rgb> active_fg;
  std::optional<Rgb> active_bg;
  for (int row = 0; row < current.rows(); ++row) {
    for (int col = 0; col < current.cols(); ++col) {
      const Cell& cell = current.at(col, row);
      if (!full_repaint && sameCell(cell, previous_.at(col, row), mono)) {
        continue;
      }

      appendCursorMove(result.bytes, row + 1, col + 1);
      if (truecolor) {
        if (!active_fg.has_value() || !sameColor(*active_fg, cell.fg)) {
          appendSgrFg(result.bytes, cell.fg);
          active_fg = cell.fg;
        }
        if (!active_bg.has_value() || !sameColor(*active_bg, cell.bg)) {
          appendSgrBg(result.bytes, cell.bg);
          active_bg = cell.bg;
        }
      }
      appendUtf8(result.bytes, cell.glyph);
      ++result.changed_cells;
    }
  }

  previous_ = current;
  has_previous_ = true;
  return result;
}

void DiffEmitter::reset() {
  has_previous_ = false;
  previous_ = CellBuffer{};
}

}  // namespace contourtty
