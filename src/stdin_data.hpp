#pragma once

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

std::optional<PlotKind> parsePlotKind(std::string_view value) noexcept;
std::vector<double> parseStdinDataNumbers(std::string_view text);
std::vector<double> spectrumMagnitudes(std::span<const double> samples);

}  // namespace contourtty
