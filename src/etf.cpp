#include "etf.hpp"

#include "worker_count.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <stdexcept>
#include <thread>
#include <vector>

namespace strok {
namespace {

constexpr double kEpsilon = 1e-12;

struct UnitVector {
  double x = 0.0;
  double y = 0.0;
};

void validateGradientField(const GradientField& gradients) {
  if (gradients.width <= 0 || gradients.height <= 0 ||
      gradients.values.size() != static_cast<std::size_t>(gradients.width) * static_cast<std::size_t>(gradients.height)) {
    throw std::invalid_argument("invalid gradient field");
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

std::size_t indexFor(const GradientField& gradients, int x, int y) {
  return static_cast<std::size_t>(y) * static_cast<std::size_t>(gradients.width) + static_cast<std::size_t>(x);
}

int clampInt(int value, int low, int high) {
  return std::min(std::max(value, low), high);
}

Gradient sampleClamped(const GradientField& gradients, int x, int y) {
  const int clamped_x = clampInt(x, 0, gradients.width - 1);
  const int clamped_y = clampInt(y, 0, gradients.height - 1);
  return gradients.values[indexFor(gradients, clamped_x, clamped_y)];
}

double magnitude(Gradient gradient) {
  return std::hypot(gradient.gx, gradient.gy);
}

UnitVector unit(Gradient gradient) {
  const double mag = magnitude(gradient);
  if (mag <= kEpsilon) {
    return {};
  }
  return UnitVector{.x = gradient.gx / mag, .y = gradient.gy / mag};
}

double sampleMagnitudeClamped(const GradientField& gradients, int x, int y) {
  return magnitude(sampleClamped(gradients, x, y));
}

}  // namespace

GradientField smoothEtfGradients(const GradientField& gradients, int iterations) {
  validateGradientField(gradients);
  if (iterations < 0) {
    throw std::invalid_argument("ETF iterations must be non-negative");
  }
  if (iterations == 0) {
    return gradients;
  }

  GradientField current = gradients;
  for (int iteration = 0; iteration < iterations; ++iteration) {
    GradientField next = current;
    parallelRows(current.height, current.width * current.height, [&](int row_begin, int row_end) {
      for (int y = row_begin; y < row_end; ++y) {
        for (int x = 0; x < current.width; ++x) {
          const std::size_t index = indexFor(current, x, y);
          const double original_magnitude = magnitude(gradients.values[index]);
          if (original_magnitude <= kEpsilon) {
            next.values[index] = Gradient{};
            continue;
          }

          const UnitVector center = unit(current.values[index]);
          double sx = 0.0;
          double sy = 0.0;
          double total_weight = 0.0;
          for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
              const Gradient neighbor_gradient = sampleClamped(current, x + dx, y + dy);
              const double neighbor_magnitude = magnitude(neighbor_gradient);
              if (neighbor_magnitude <= kEpsilon) {
                continue;
              }
              const UnitVector neighbor = unit(neighbor_gradient);
              const double dot = center.x * neighbor.x + center.y * neighbor.y;
              const double sign = dot < 0.0 ? -1.0 : 1.0;
              const double weight = neighbor_magnitude * std::abs(dot);
              sx += sign * neighbor.x * weight;
              sy += sign * neighbor.y * weight;
              total_weight += weight;
            }
          }

          const double smoothed_magnitude = std::hypot(sx, sy);
          if (total_weight <= kEpsilon || smoothed_magnitude <= kEpsilon) {
            next.values[index] = gradients.values[index];
            continue;
          }
          next.values[index] = Gradient{
            .gx = (sx / smoothed_magnitude) * original_magnitude,
            .gy = (sy / smoothed_magnitude) * original_magnitude,
          };
        }
      }
    });
    current = std::move(next);
  }
  return current;
}

LuminanceField coherentLineField(const GradientField& gradients, double threshold) {
  validateGradientField(gradients);
  if (threshold < 0.0) {
    throw std::invalid_argument("CLD threshold must be non-negative");
  }

  LuminanceField field;
  field.width = gradients.width;
  field.height = gradients.height;
  field.values.assign(gradients.values.size(), 0.0);
  parallelRows(gradients.height, gradients.width * gradients.height, [&](int row_begin, int row_end) {
    for (int y = row_begin; y < row_end; ++y) {
      for (int x = 0; x < gradients.width; ++x) {
        const std::size_t index = indexFor(gradients, x, y);
        const Gradient gradient = gradients.values[index];
        const double center_magnitude = magnitude(gradient);
        if (center_magnitude <= threshold || center_magnitude <= kEpsilon) {
          continue;
        }

        const double tx = -gradient.gy / center_magnitude;
        const double ty = gradient.gx / center_magnitude;
        double sum = 0.0;
        double weight_sum = 0.0;
        for (int offset = -2; offset <= 2; ++offset) {
          const double weight = static_cast<double>(3 - std::abs(offset));
          const int sx = static_cast<int>(std::lround(static_cast<double>(x) + tx * static_cast<double>(offset)));
          const int sy = static_cast<int>(std::lround(static_cast<double>(y) + ty * static_cast<double>(offset)));
          sum += sampleMagnitudeClamped(gradients, sx, sy) * weight;
          weight_sum += weight;
        }
        const double value = weight_sum > 0.0 ? sum / weight_sum : 0.0;
        field.values[index] = value > threshold ? value : 0.0;
      }
    }
  });
  return field;
}

}  // namespace strok
