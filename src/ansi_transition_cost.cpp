#include "ansi_transition_cost.hpp"

#include <stdexcept>

namespace strok {
namespace {

std::size_t decimalDigits(int value) {
  std::size_t digits = 1;
  while (value >= 10) {
    value /= 10;
    ++digits;
  }
  return digits;
}

std::size_t cursorMoveBytes(int row, int col) {
  // ESC [ <row> ; <col> H
  return 4U + decimalDigits(row) + decimalDigits(col);
}

std::size_t truecolorSgrBytes(Rgb color) {
  // ESC [ 38/48 ; 2 ; <red> ; <green> ; <blue> m
  return 10U + decimalDigits(color.r) + decimalDigits(color.g) + decimalDigits(color.b);
}

std::size_t utf8Bytes(char32_t glyph) {
  if (glyph <= 0x7fU) {
    return 1;
  }
  if (glyph <= 0x7ffU) {
    return 2;
  }
  if (glyph <= 0xffffU) {
    if (glyph >= 0xd800U && glyph <= 0xdfffU) {
      throw std::invalid_argument("invalid unicode surrogate");
    }
    return 3;
  }
  if (glyph <= 0x10ffffU) {
    return 4;
  }
  throw std::invalid_argument("invalid unicode codepoint");
}

bool hasKnownSingleColumnWidth(char32_t glyph) noexcept {
  return (glyph >= U' ' && glyph <= U'~') ||
         (glyph >= U'\u2500' && glyph <= U'\u259f') ||
         (glyph >= U'\u2800' && glyph <= U'\u28ff');
}

}  // namespace

AnsiTransitionEstimate estimateAnsiCellTransition(const Cell& previous,
                                                   const Cell& current,
                                                   int terminal_row,
                                                   int terminal_col,
                                                   AnsiTransitionContext context) {
  if (terminal_row <= 0 || terminal_col <= 0) {
    throw std::invalid_argument("terminal position is 1-based");
  }
  AnsiTransitionEstimate estimate{.next_context = context};
  if (previous == current) {
    return estimate;
  }

  const bool continues_cursor_run = context.previous_emitted_single_column &&
                                    context.previous_emitted_row == terminal_row &&
                                    context.previous_emitted_col + 1 == terminal_col;
  if (!continues_cursor_run) {
    estimate.ansi_bytes += cursorMoveBytes(terminal_row, terminal_col);
  }
  if (!context.active_foreground.has_value() || *context.active_foreground != current.fg) {
    estimate.ansi_bytes += truecolorSgrBytes(current.fg);
    estimate.next_context.active_foreground = current.fg;
  }
  if (!context.active_background.has_value() || *context.active_background != current.bg) {
    estimate.ansi_bytes += truecolorSgrBytes(current.bg);
    estimate.next_context.active_background = current.bg;
  }
  estimate.ansi_bytes += utf8Bytes(current.glyph);
  estimate.update_units = 1;
  estimate.next_context.previous_emitted_row = terminal_row;
  estimate.next_context.previous_emitted_col = terminal_col;
  estimate.next_context.previous_emitted_single_column = hasKnownSingleColumnWidth(current.glyph);
  return estimate;
}

}  // namespace strok
