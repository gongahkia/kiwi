#include "stdin_data.hpp"

#include <charconv>
#include <algorithm>
#include <cmath>
#include <complex>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <stdexcept>
#include <string>

namespace contourtty {
namespace {

constexpr double kPi = 3.141592653589793238462643383279502884;

bool separator(char ch) noexcept {
  return ch == ',' || ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
}

PlotRaster blankRaster(int width, int height) {
  if (width <= 0 || height <= 0) {
    throw std::invalid_argument("plot dimensions must be positive");
  }
  return PlotRaster{
    .width = width,
    .height = height,
    .values = std::vector<double>(static_cast<std::size_t>(width) * static_cast<std::size_t>(height), 0.0),
  };
}

void setPixel(PlotRaster* raster, int x, int y, double value) {
  if (x < 0 || y < 0 || x >= raster->width || y >= raster->height) {
    return;
  }
  double& dst = raster->values[static_cast<std::size_t>(y) * static_cast<std::size_t>(raster->width) + static_cast<std::size_t>(x)];
  dst = std::max(dst, std::clamp(value, 0.0, 1.0));
}

std::pair<double, double> minMax(std::span<const double> samples) {
  if (samples.empty()) {
    return {0.0, 1.0};
  }
  auto [min_it, max_it] = std::minmax_element(samples.begin(), samples.end());
  if (*min_it == *max_it) {
    const double center = *min_it;
    return {center - 1.0, center + 1.0};
  }
  return {*min_it, *max_it};
}

double normalize(double value, double min_value, double max_value) {
  return std::clamp((value - min_value) / (max_value - min_value), 0.0, 1.0);
}

std::size_t sampleIndexForColumn(int x, int width, std::size_t sample_count) {
  if (sample_count <= 1 || width <= 1) {
    return 0;
  }
  return static_cast<std::size_t>(std::llround((static_cast<double>(x) * static_cast<double>(sample_count - 1)) / static_cast<double>(width - 1)));
}

void drawLine(PlotRaster* raster, int x0, int y0, int x1, int y1) {
  const int dx = std::abs(x1 - x0);
  const int sx = x0 < x1 ? 1 : -1;
  const int dy = -std::abs(y1 - y0);
  const int sy = y0 < y1 ? 1 : -1;
  int error = dx + dy;
  while (true) {
    setPixel(raster, x0, y0, 1.0);
    if (x0 == x1 && y0 == y1) {
      break;
    }
    const int twice_error = 2 * error;
    if (twice_error >= dy) {
      error += dy;
      x0 += sx;
    }
    if (twice_error <= dx) {
      error += dx;
      y0 += sy;
    }
  }
}

std::size_t nextPowerOfTwo(std::size_t value) {
  std::size_t power = 1;
  while (power < value) {
    power *= 2;
  }
  return power;
}

void fft(std::vector<std::complex<double>>* values) {
  const std::size_t n = values->size();
  if (n <= 1) {
    return;
  }
  std::vector<std::complex<double>> even;
  std::vector<std::complex<double>> odd;
  even.reserve(n / 2);
  odd.reserve(n / 2);
  for (std::size_t i = 0; i < n; ++i) {
    (i % 2 == 0 ? even : odd).push_back((*values)[i]);
  }
  fft(&even);
  fft(&odd);
  for (std::size_t k = 0; k < n / 2; ++k) {
    const double angle = -2.0 * kPi * static_cast<double>(k) / static_cast<double>(n);
    const std::complex<double> twiddle(std::cos(angle), std::sin(angle));
    (*values)[k] = even[k] + twiddle * odd[k];
    (*values)[k + n / 2] = even[k] - twiddle * odd[k];
  }
}

}  // namespace

double PlotRaster::at(int x, int y) const {
  if (x < 0 || y < 0 || x >= width || y >= height) {
    throw std::out_of_range("plot raster index out of range");
  }
  return values.at(static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x));
}

std::optional<PlotKind> parsePlotKind(std::string_view value) noexcept {
  if (value == "waveform") {
    return PlotKind::Waveform;
  }
  if (value == "spectrum") {
    return PlotKind::Spectrum;
  }
  if (value == "heatmap") {
    return PlotKind::Heatmap;
  }
  return std::nullopt;
}

std::vector<double> parseStdinDataNumbers(std::string_view text) {
  std::vector<double> values;
  std::size_t start = 0;
  while (start < text.size()) {
    while (start < text.size() && separator(text[start])) {
      ++start;
    }
    if (start >= text.size()) {
      break;
    }
    std::size_t end = start;
    while (end < text.size() && !separator(text[end])) {
      ++end;
    }
    const std::string token(text.substr(start, end - start));
    char* parsed_end = nullptr;
    const double value = std::strtod(token.c_str(), &parsed_end);
    if (parsed_end == token.c_str() || *parsed_end != '\0') {
      throw std::invalid_argument("invalid numeric stdin token: " + token);
    }
    values.push_back(value);
    start = end;
  }
  return values;
}

std::vector<double> spectrumMagnitudes(std::span<const double> samples) {
  if (samples.empty()) {
    return {};
  }
  std::vector<std::complex<double>> values(nextPowerOfTwo(samples.size()), std::complex<double>{});
  for (std::size_t i = 0; i < samples.size(); ++i) {
    values[i] = samples[i];
  }
  fft(&values);
  std::vector<double> magnitudes(values.size() / 2 + 1);
  for (std::size_t i = 0; i < magnitudes.size(); ++i) {
    magnitudes[i] = std::abs(values[i]);
  }
  return magnitudes;
}

PlotRaster renderWaveformPlot(std::span<const double> samples, int width, int height) {
  PlotRaster raster = blankRaster(width, height);
  if (samples.empty()) {
    return raster;
  }
  const auto [min_value, max_value] = minMax(samples);
  int previous_x = 0;
  int previous_y = 0;
  bool has_previous = false;
  for (int x = 0; x < width; ++x) {
    const std::size_t sample_index = sampleIndexForColumn(x, width, samples.size());
    const double normalized = normalize(samples[sample_index], min_value, max_value);
    const int y = std::clamp(static_cast<int>(std::lround((1.0 - normalized) * static_cast<double>(height - 1))), 0, height - 1);
    if (has_previous) {
      drawLine(&raster, previous_x, previous_y, x, y);
    } else {
      setPixel(&raster, x, y, 1.0);
    }
    previous_x = x;
    previous_y = y;
    has_previous = true;
  }
  return raster;
}

PlotRaster renderSpectrumPlot(std::span<const double> samples, int width, int height) {
  PlotRaster raster = blankRaster(width, height);
  const std::vector<double> magnitudes = spectrumMagnitudes(samples);
  if (magnitudes.empty()) {
    return raster;
  }
  const double max_value = *std::max_element(magnitudes.begin(), magnitudes.end());
  if (max_value <= 0.0) {
    return raster;
  }
  for (int x = 0; x < width; ++x) {
    const std::size_t bin = sampleIndexForColumn(x, width, magnitudes.size());
    const double normalized = std::clamp(magnitudes[bin] / max_value, 0.0, 1.0);
    const int bar_height = std::max(1, static_cast<int>(std::lround(normalized * static_cast<double>(height))));
    for (int y = height - bar_height; y < height; ++y) {
      setPixel(&raster, x, y, normalized);
    }
  }
  return raster;
}

PlotRaster renderHeatmapPlot(std::span<const double> samples, int width, int height) {
  PlotRaster raster = blankRaster(width, height);
  if (samples.empty()) {
    return raster;
  }
  const std::size_t cells = static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
  const std::size_t start = samples.size() > cells ? samples.size() - cells : 0;
  const std::span<const double> window = samples.subspan(start);
  const auto [min_value, max_value] = minMax(window);
  for (std::size_t i = 0; i < window.size(); ++i) {
    const int x = static_cast<int>(i % static_cast<std::size_t>(width));
    const int y = static_cast<int>(i / static_cast<std::size_t>(width));
    setPixel(&raster, x, y, normalize(window[i], min_value, max_value));
  }
  return raster;
}

PlotRaster renderPlot(PlotKind kind, std::span<const double> samples, int width, int height) {
  switch (kind) {
    case PlotKind::Waveform:
      return renderWaveformPlot(samples, width, height);
    case PlotKind::Spectrum:
      return renderSpectrumPlot(samples, width, height);
    case PlotKind::Heatmap:
      return renderHeatmapPlot(samples, width, height);
  }
  throw std::invalid_argument("unknown plot kind");
}

Frame plotRasterToFrame(const PlotRaster& raster, int64_t pts_us, Rgb ink, Rgb background) {
  if (raster.width <= 0 || raster.height <= 0 || raster.values.size() != static_cast<std::size_t>(raster.width) * static_cast<std::size_t>(raster.height)) {
    throw std::invalid_argument("invalid plot raster");
  }
  Frame frame{
    .w = raster.width,
    .h = raster.height,
    .pts_us = pts_us,
  };
  frame.rgb.resize(static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h) * 3U);
  for (int y = 0; y < raster.height; ++y) {
    for (int x = 0; x < raster.width; ++x) {
      const double value = std::clamp(raster.at(x, y), 0.0, 1.0);
      const std::size_t offset = (static_cast<std::size_t>(y) * static_cast<std::size_t>(raster.width) + static_cast<std::size_t>(x)) * 3U;
      frame.rgb[offset] = static_cast<uint8_t>(std::lround(static_cast<double>(background.r) * (1.0 - value) + static_cast<double>(ink.r) * value));
      frame.rgb[offset + 1U] = static_cast<uint8_t>(std::lround(static_cast<double>(background.g) * (1.0 - value) + static_cast<double>(ink.g) * value));
      frame.rgb[offset + 2U] = static_cast<uint8_t>(std::lround(static_cast<double>(background.b) * (1.0 - value) + static_cast<double>(ink.b) * value));
    }
  }
  return frame;
}

}  // namespace contourtty
