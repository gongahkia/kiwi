#pragma once

#include "frame.hpp"
#include "luminance.hpp"

#include <optional>
#include <span>
#include <string_view>
#include <vector>

namespace contourtty {

enum class PlotKind {
  Waveform,
  Spectrum,
  Heatmap,
};

struct PlotRaster {
  int width = 0;
  int height = 0;
  std::vector<double> values;

  double at(int x, int y) const;
};

std::optional<PlotKind> parsePlotKind(std::string_view value) noexcept;
std::vector<double> parseStdinDataNumbers(std::string_view text);
std::vector<double> spectrumMagnitudes(std::span<const double> samples);
PlotRaster renderWaveformPlot(std::span<const double> samples, int width, int height);
PlotRaster renderSpectrumPlot(std::span<const double> samples, int width, int height);
PlotRaster renderHeatmapPlot(std::span<const double> samples, int width, int height);
PlotRaster renderPlot(PlotKind kind, std::span<const double> samples, int width, int height);
Frame plotRasterToFrame(const PlotRaster& raster, int64_t pts_us = 0, Rgb ink = Rgb{.r = 0, .g = 255, .b = 128}, Rgb background = Rgb{});

}  // namespace contourtty
