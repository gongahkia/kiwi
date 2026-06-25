#include "kuwahara.hpp"

#include "worker_count.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <thread>
#include <vector>

namespace contourtty {
namespace {

constexpr double kPi = 3.14159265358979323846;

struct SectorStats {
  double r = 0.0;
  double g = 0.0;
  double b = 0.0;
  double l = 0.0;
  double l2 = 0.0;
  int count = 0;
};

void validateFrame(const Frame& frame) {
  if (frame.w <= 0 || frame.h <= 0 ||
      frame.rgb.size() != static_cast<std::size_t>(frame.w) * static_cast<std::size_t>(frame.h) * 3U) {
    throw std::invalid_argument("invalid frame");
  }
}

int workerCount(int rows, int items) {
  if (rows < 2 || items < 8192) {
    return 1;
  }
  const unsigned hardware = std::thread::hardware_concurrency();
  const int max_workers = boundedWorkerCount(static_cast<int>(hardware == 0 ? 2 : hardware));
  return std::min(rows, max_workers);
}

template <typename Function>
void parallelRows(int rows, int items, Function function) {
  const int workers = workerCount(rows, items);
  if (workers == 1) {
    function(0, rows);
    return;
  }

  std::vector<std::thread> threads;
  threads.reserve(static_cast<std::size_t>(workers - 1));
  for (int worker = 1; worker < workers; ++worker) {
    const int row_begin = (rows * worker) / workers;
    const int row_end = (rows * (worker + 1)) / workers;
    threads.emplace_back(function, row_begin, row_end);
  }
  function(0, rows / workers);
  for (std::thread& thread : threads) {
    thread.join();
  }
}

std::size_t pixelIndex(const Frame& frame, int x, int y) {
  return (static_cast<std::size_t>(y) * static_cast<std::size_t>(frame.w) + static_cast<std::size_t>(x)) * 3U;
}

double luminance(uint8_t r, uint8_t g, uint8_t b) {
  return 0.2126 * static_cast<double>(r) + 0.7152 * static_cast<double>(g) + 0.0722 * static_cast<double>(b);
}

int sectorForOffset(int dx, int dy) {
  if (dx == 0 && dy == 0) {
    return -1;
  }
  double angle = std::atan2(static_cast<double>(dy), static_cast<double>(dx));
  if (angle < 0.0) {
    angle += 2.0 * kPi;
  }
  return static_cast<int>(std::floor((angle + kPi / 8.0) / (kPi / 4.0))) % 8;
}

void addSample(SectorStats* stats, uint8_t r, uint8_t g, uint8_t b) {
  const double luma = luminance(r, g, b);
  stats->r += static_cast<double>(r);
  stats->g += static_cast<double>(g);
  stats->b += static_cast<double>(b);
  stats->l += luma;
  stats->l2 += luma * luma;
  ++stats->count;
}

double variance(const SectorStats& stats) {
  if (stats.count <= 0) {
    return std::numeric_limits<double>::infinity();
  }
  const double count = static_cast<double>(stats.count);
  const double mean = stats.l / count;
  return std::max(0.0, stats.l2 / count - mean * mean);
}

uint8_t meanChannel(double sum, int count) {
  return static_cast<uint8_t>(std::clamp(std::lround(sum / static_cast<double>(count)), 0L, 255L));
}

}  // namespace

Frame applyKuwaharaFilter(const Frame& frame, int radius) {
  validateFrame(frame);
  if (radius <= 0 || radius > 8) {
    throw std::invalid_argument("Kuwahara radius must be in 1...8");
  }

  Frame output = frame;
  parallelRows(frame.h, frame.w * frame.h, [&](int row_begin, int row_end) {
    for (int y = row_begin; y < row_end; ++y) {
      for (int x = 0; x < frame.w; ++x) {
        std::array<SectorStats, 8> sectors;
        for (int dy = -radius; dy <= radius; ++dy) {
          const int sy = std::clamp(y + dy, 0, frame.h - 1);
          for (int dx = -radius; dx <= radius; ++dx) {
            if (dx * dx + dy * dy > radius * radius) {
              continue;
            }
            const int sx = std::clamp(x + dx, 0, frame.w - 1);
            const std::size_t source = pixelIndex(frame, sx, sy);
            const uint8_t r = frame.rgb[source];
            const uint8_t g = frame.rgb[source + 1];
            const uint8_t b = frame.rgb[source + 2];
            const int sector = sectorForOffset(dx, dy);
            if (sector < 0) {
              for (SectorStats& stats : sectors) {
                addSample(&stats, r, g, b);
              }
            } else {
              addSample(&sectors[static_cast<std::size_t>(sector)], r, g, b);
            }
          }
        }

        const SectorStats* best = &sectors[0];
        double best_variance = variance(*best);
        for (const SectorStats& stats : sectors) {
          const double candidate = variance(stats);
          if (candidate < best_variance) {
            best = &stats;
            best_variance = candidate;
          }
        }
        const std::size_t target = pixelIndex(output, x, y);
        output.rgb[target] = meanChannel(best->r, best->count);
        output.rgb[target + 1] = meanChannel(best->g, best->count);
        output.rgb[target + 2] = meanChannel(best->b, best->count);
      }
    }
  });
  return output;
}

}  // namespace contourtty
