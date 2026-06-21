#include "stdin_data.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

bool near(double lhs, double rhs, double eps = 1e-9) {
  return std::abs(lhs - rhs) <= eps;
}

}  // namespace

int main() {
  {
    expect(contourtty::parsePlotKind("waveform") == contourtty::PlotKind::Waveform, "waveform plot parses");
    expect(contourtty::parsePlotKind("spectrum") == contourtty::PlotKind::Spectrum, "spectrum plot parses");
    expect(contourtty::parsePlotKind("heatmap") == contourtty::PlotKind::Heatmap, "heatmap plot parses");
    expect(!contourtty::parsePlotKind("bad").has_value(), "bad plot rejected");
  }

  {
    const std::vector<double> values = contourtty::parseStdinDataNumbers("1, 2\n-3.5\t4e1");
    expect(values.size() == 4, "stdin parser value count");
    expect(near(values[0], 1.0), "stdin parser first value");
    expect(near(values[2], -3.5), "stdin parser negative value");
    expect(near(values[3], 40.0), "stdin parser exponent value");
  }

  {
    bool threw = false;
    try {
      (void)contourtty::parseStdinDataNumbers("1 nope 2");
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "stdin parser rejects bad token");
  }

  {
    const std::vector<double> impulse{1.0, 0.0, 0.0, 0.0};
    const std::vector<double> magnitudes = contourtty::spectrumMagnitudes(impulse);
    expect(magnitudes.size() == 3, "spectrum stores nonnegative bins");
    expect(near(magnitudes[0], 1.0), "impulse dc magnitude");
    expect(near(magnitudes[1], 1.0), "impulse bin 1 magnitude");
    expect(near(magnitudes[2], 1.0), "impulse nyquist magnitude");
  }
}
