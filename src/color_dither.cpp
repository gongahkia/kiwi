#include "color_dither.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace strok {
namespace {

struct ChannelError {
  double r = 0.0;
  double g = 0.0;
  double b = 0.0;
};

Rgb clampRgb(double r, double g, double b) {
  return Rgb{
    .r = static_cast<uint8_t>(std::clamp(static_cast<int>(std::lround(r)), 0, 255)),
    .g = static_cast<uint8_t>(std::clamp(static_cast<int>(std::lround(g)), 0, 255)),
    .b = static_cast<uint8_t>(std::clamp(static_cast<int>(std::lround(b)), 0, 255)),
  };
}

Rgb addError(Rgb color, ChannelError error) {
  return clampRgb(static_cast<double>(color.r) + error.r,
                  static_cast<double>(color.g) + error.g,
                  static_cast<double>(color.b) + error.b);
}

ChannelError quantizationError(Rgb source, Rgb quantized) {
  return ChannelError{
    .r = static_cast<double>(source.r) - static_cast<double>(quantized.r),
    .g = static_cast<double>(source.g) - static_cast<double>(quantized.g),
    .b = static_cast<double>(source.b) - static_cast<double>(quantized.b),
  };
}

void addScaledError(std::vector<ChannelError>* errors, int cols, int rows, int col, int row, ChannelError error, double scale) {
  if (col < 0 || row < 0 || col >= cols || row >= rows) {
    return;
  }
  ChannelError& target = errors->at(static_cast<std::size_t>(row) * static_cast<std::size_t>(cols) + static_cast<std::size_t>(col));
  target.r += error.r * scale;
  target.g += error.g * scale;
  target.b += error.b * scale;
}

Rgb nearestPaletteColor(Rgb color, ColorMode mode) {
  switch (mode) {
    case ColorMode::Color256:
      return xterm256Color(quantizeXterm256(color));
    case ColorMode::Color16:
      return ansi16Color(quantizeAnsi16(color));
    case ColorMode::Truecolor:
    case ColorMode::Mono:
      return color;
  }
  return color;
}

int orderedAmplitude(ColorMode mode) noexcept {
  return mode == ColorMode::Color16 ? 32 : 16;
}

Rgb ditherCellColor(Rgb source, ColorMode mode, std::vector<ChannelError>* errors, int cols, int rows, int col, int row) {
  const std::size_t index = static_cast<std::size_t>(row) * static_cast<std::size_t>(cols) + static_cast<std::size_t>(col);
  const Rgb corrected = addError(source, errors->at(index));
  const Rgb quantized = nearestPaletteColor(corrected, mode);
  const ChannelError error = quantizationError(corrected, quantized);
  addScaledError(errors, cols, rows, col + 1, row, error, 7.0 / 16.0);
  addScaledError(errors, cols, rows, col - 1, row + 1, error, 3.0 / 16.0);
  addScaledError(errors, cols, rows, col, row + 1, error, 5.0 / 16.0);
  addScaledError(errors, cols, rows, col + 1, row + 1, error, 1.0 / 16.0);
  return quantized;
}

}  // namespace

bool supportsPaletteDither(ColorMode mode) noexcept {
  return mode == ColorMode::Color256 || mode == ColorMode::Color16;
}

CellBuffer applyPaletteDither(const CellBuffer& input, ColorMode mode, DitherMode dither_mode) {
  if (!supportsPaletteDither(mode)) {
    return input;
  }
  if (dither_mode == DitherMode::FloydSteinberg) {
    return applyFloydSteinbergDither(input, mode);
  }
  CellBuffer output(input.cols(), input.rows());
  for (int row = 0; row < input.rows(); ++row) {
    for (int col = 0; col < input.cols(); ++col) {
      const Cell& source = input.at(col, row);
      Cell& target = output.at(col, row);
      target.glyph = source.glyph;
      target.fg = source.fg;
      target.bg = source.bg;
      if (dither_mode == DitherMode::Ordered) {
        target.fg = applyOrderedDither(target.fg, row, col, orderedAmplitude(mode));
        target.bg = applyOrderedDither(target.bg, row, col, orderedAmplitude(mode));
      }
      target.fg = nearestPaletteColor(target.fg, mode);
      target.bg = nearestPaletteColor(target.bg, mode);
    }
  }
  return output;
}

CellBuffer applyFloydSteinbergDither(const CellBuffer& input, ColorMode mode) {
  if (!supportsPaletteDither(mode)) {
    return input;
  }
  CellBuffer output(input.cols(), input.rows());
  std::vector<ChannelError> fg_errors(input.size());
  std::vector<ChannelError> bg_errors(input.size());
  for (int row = 0; row < input.rows(); ++row) {
    for (int col = 0; col < input.cols(); ++col) {
      const Cell& source = input.at(col, row);
      Cell& target = output.at(col, row);
      target.glyph = source.glyph;
      target.fg = ditherCellColor(source.fg, mode, &fg_errors, input.cols(), input.rows(), col, row);
      target.bg = ditherCellColor(source.bg, mode, &bg_errors, input.cols(), input.rows(), col, row);
    }
  }
  return output;
}

}  // namespace strok
