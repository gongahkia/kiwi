#pragma once

#include <strok/cell_buffer.hpp>

#include <cstddef>
#include <optional>

namespace strok {

// Models one DiffEmitter ANSI transition with truecolor, no dithering, stable
// options, and no full repaint. It is a side-effect-free cost model, not an
// emitter: callers retain and pass the local cursor/style context explicitly.
struct AnsiTransitionContext {
  std::optional<Rgb> active_foreground;
  std::optional<Rgb> active_background;
  int previous_emitted_row = -1;
  int previous_emitted_col = -1;
  bool previous_emitted_single_column = false;

  bool operator==(const AnsiTransitionContext&) const = default;
};

struct AnsiTransitionEstimate {
  // Encoded ANSI byte count and terminal-cell update units are intentionally
  // separate: callers may use one or both without treating them as equivalent.
  std::size_t ansi_bytes = 0;
  std::size_t update_units = 0;
  AnsiTransitionContext next_context;
};

AnsiTransitionEstimate estimateAnsiCellTransition(const Cell& previous,
                                                   const Cell& current,
                                                   int terminal_row,
                                                   int terminal_col,
                                                   AnsiTransitionContext context = {});

}  // namespace strok
