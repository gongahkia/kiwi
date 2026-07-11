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
    expect(strok::parsePlotKind("waveform") == strok::PlotKind::Waveform, "waveform plot parses");
    expect(strok::parsePlotKind("spectrum") == strok::PlotKind::Spectrum, "spectrum plot parses");
    expect(strok::parsePlotKind("heatmap") == strok::PlotKind::Heatmap, "heatmap plot parses");
    expect(!strok::parsePlotKind("bad").has_value(), "bad plot rejected");
  }

  {
    const std::vector<double> values = strok::parseStdinDataNumbers("1, 2\n-3.5\t4e1");
    expect(values.size() == 4, "stdin parser value count");
    expect(near(values[0], 1.0), "stdin parser first value");
    expect(near(values[2], -3.5), "stdin parser negative value");
    expect(near(values[3], 40.0), "stdin parser exponent value");
  }

  {
    bool threw = false;
    try {
      (void)strok::parseStdinDataNumbers("1 nope 2");
    } catch (const std::invalid_argument&) {
      threw = true;
    }
    expect(threw, "stdin parser rejects bad token");
  }

  {
    const std::vector<double> impulse{1.0, 0.0, 0.0, 0.0};
    const std::vector<double> magnitudes = strok::spectrumMagnitudes(impulse);
    expect(magnitudes.size() == 3, "spectrum stores nonnegative bins");
    expect(near(magnitudes[0], 1.0), "impulse dc magnitude");
    expect(near(magnitudes[1], 1.0), "impulse bin 1 magnitude");
    expect(near(magnitudes[2], 1.0), "impulse nyquist magnitude");
  }

  {
    const std::vector<double> samples{-1.0, 0.0, 1.0};
    const strok::PlotRaster raster = strok::renderWaveformPlot(samples, 3, 3);
    expect(raster.width == 3 && raster.height == 3, "waveform raster dimensions");
    expect(raster.at(0, 2) == 1.0, "waveform low sample bottom");
    expect(raster.at(1, 1) == 1.0, "waveform middle sample center");
    expect(raster.at(2, 0) == 1.0, "waveform high sample top");
  }

  {
    const std::vector<double> samples{1.0, 0.0, 0.0, 0.0};
    const strok::PlotRaster raster = strok::renderSpectrumPlot(samples, 3, 4);
    expect(raster.at(0, 0) > 0.0, "spectrum first bin reaches top");
    expect(raster.at(1, 3) > 0.0, "spectrum middle bin reaches bottom");
    expect(raster.at(2, 3) > 0.0, "spectrum last bin reaches bottom");
  }

  {
    const std::vector<double> samples{0.0, 1.0, 2.0, 3.0};
    const strok::PlotRaster raster = strok::renderHeatmapPlot(samples, 2, 2);
    expect(near(raster.at(0, 0), 0.0), "heatmap min");
    expect(near(raster.at(1, 1), 1.0), "heatmap max");
    expect(raster.at(1, 0) > raster.at(0, 0), "heatmap rising");
  }

  {
    strok::PlotRaster raster{
      .width = 2,
      .height = 1,
      .values = {1.0, 0.0},
    };
    const strok::Frame frame = strok::plotRasterToFrame(raster, 123, strok::Rgb{.r = 10, .g = 20, .b = 30}, strok::Rgb{.r = 1, .g = 2, .b = 3});
    expect(frame.w == 2 && frame.h == 1, "plot frame dimensions");
    expect(frame.pts_us == 123, "plot frame pts");
    expect(frame.rgb[0] == 10 && frame.rgb[1] == 20 && frame.rgb[2] == 30, "plot frame ink pixel");
    expect(frame.rgb[3] == 1 && frame.rgb[4] == 2 && frame.rgb[5] == 3, "plot frame background pixel");
  }
}
