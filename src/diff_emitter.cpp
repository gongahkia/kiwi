#include "diff_emitter.hpp"

#include "ansi.hpp"
#include "color_dither.hpp"
#include "posterize.hpp"

#include <cmath>
#include <optional>

namespace strok {
namespace {

bool sameColor(Rgb lhs, Rgb rhs) noexcept {
  return lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b;
}

double oklabDistance(Rgb lhs, Rgb rhs) noexcept {
  const Oklab a = rgbToOklab(lhs);
  const Oklab b = rgbToOklab(rhs);
  const double dl = a.l - b.l;
  const double da = a.a - b.a;
  const double db = a.b - b.b;
  return std::sqrt(dl * dl + da * da + db * db);
}

bool equivalentColor(Rgb lhs, Rgb rhs, double eps) noexcept {
  if (sameColor(lhs, rhs)) {
    return true;
  }
  return eps > 0.0 && oklabDistance(lhs, rhs) <= eps;
}

bool sameCell(const Cell& lhs, const Cell& rhs, bool mono, double diff_oklab_eps) noexcept {
  if (mono) {
    return lhs.glyph == rhs.glyph;
  }
  return lhs.glyph == rhs.glyph &&
         equivalentColor(lhs.fg, rhs.fg, diff_oklab_eps) &&
         equivalentColor(lhs.bg, rhs.bg, diff_oklab_eps);
}

bool sameOptions(EmissionOptions lhs, EmissionOptions rhs) noexcept {
  return lhs.color_mode == rhs.color_mode && lhs.dither_mode == rhs.dither_mode &&
         lhs.diff_oklab_eps == rhs.diff_oklab_eps &&
         lhs.origin_row == rhs.origin_row && lhs.origin_col == rhs.origin_col;
}

Rgb ditherColor(Rgb color, int row, int col, EmissionOptions options) {
  if (options.dither_mode != DitherMode::Ordered || !supportsPaletteDither(options.color_mode)) {
    return color;
  }
  const int amplitude = options.color_mode == ColorMode::Color16 ? 32 : 16;
  return applyOrderedDither(color, row, col, amplitude);
}

void appendFg(std::string& out, Rgb color, int row, int col, EmissionOptions options) {
  color = ditherColor(color, row, col, options);
  switch (options.color_mode) {
    case ColorMode::Truecolor:
      appendSgrFg(out, color);
      return;
    case ColorMode::Color256:
      appendSgrFg256(out, quantizeXterm256(color));
      return;
    case ColorMode::Color16:
      appendSgrFg16(out, quantizeAnsi16(color));
      return;
    case ColorMode::Mono:
      return;
  }
}

void appendBg(std::string& out, Rgb color, int row, int col, EmissionOptions options) {
  color = ditherColor(color, row, col, options);
  switch (options.color_mode) {
    case ColorMode::Truecolor:
      appendSgrBg(out, color);
      return;
    case ColorMode::Color256:
      appendSgrBg256(out, quantizeXterm256(color));
      return;
    case ColorMode::Color16:
      appendSgrBg16(out, quantizeAnsi16(color));
      return;
    case ColorMode::Mono:
      return;
  }
}

}  // namespace

EmissionResult DiffEmitter::emit(const CellBuffer& current, EmissionOptions options) {
  CellBuffer dithered;
  const CellBuffer* current_frame = &current;
  EmissionOptions emit_options = options;
  if (supportsPaletteDither(options.color_mode)) {
    dithered = applyPaletteDither(current, options.color_mode, options.dither_mode);
    current_frame = &dithered;
    emit_options.dither_mode = DitherMode::None;
  }
  const bool options_changed = !previous_options_.has_value() || !sameOptions(*previous_options_, options);
  const bool full_repaint = !has_previous_ || previous_.cols() != current_frame->cols() || previous_.rows() != current_frame->rows() || options_changed;
  const bool color = options.color_mode != ColorMode::Mono;
  const bool mono = !color;
  EmissionResult result;
  result.bytes.reserve(current_frame->size() * 32);
  if (full_repaint && has_previous_) {
    result.bytes += "\x1b[2J";
  }

  std::optional<Rgb> active_fg;
  std::optional<Rgb> active_bg;
  for (int row = 0; row < current_frame->rows(); ++row) {
    for (int col = 0; col < current_frame->cols(); ++col) {
      const Cell& cell = current_frame->at(col, row);
      if (!full_repaint && sameCell(cell, previous_.at(col, row), mono, options.diff_oklab_eps)) {
        continue;
      }

      appendCursorMove(result.bytes, options.origin_row + row, options.origin_col + col);
      if (color) {
        if (!active_fg.has_value() || !sameColor(*active_fg, cell.fg)) {
          appendFg(result.bytes, cell.fg, row, col, emit_options);
          active_fg = cell.fg;
        }
        if (!active_bg.has_value() || !sameColor(*active_bg, cell.bg)) {
          appendBg(result.bytes, cell.bg, row, col, emit_options);
          active_bg = cell.bg;
        }
      }
      appendUtf8(result.bytes, cell.glyph);
      ++result.changed_cells;
      if (!full_repaint) {
        previous_.at(col, row) = cell;
      }
    }
  }

  if (full_repaint) {
    previous_ = *current_frame;
  }
  previous_options_ = options;
  has_previous_ = true;
  return result;
}

void DiffEmitter::reset() {
  has_previous_ = false;
  previous_options_.reset();
  previous_ = CellBuffer{};
}

}  // namespace strok
