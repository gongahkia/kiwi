#include "stdin_data.hpp"

#include <charconv>
#include <cmath>
#include <complex>
#include <cstdlib>
#include <stdexcept>
#include <string>

namespace contourtty {
namespace {

constexpr double kPi = 3.141592653589793238462643383279502884;

bool separator(char ch) noexcept {
  return ch == ',' || ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';
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

}  // namespace contourtty
