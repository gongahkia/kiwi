#include "structure_edges.hpp"

#include "worker_count.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <optional>
#include <stdexcept>
#include <thread>
#include <vector>

#if defined(__aarch64__) && defined(__ARM_NEON)
#include <arm_neon.h>
#endif

#if defined(__x86_64__) && (defined(__clang__) || defined(__GNUC__))
#include <immintrin.h>
#endif

namespace contourtty {
namespace {

constexpr double kPi = 3.14159265358979323846;

#if defined(__x86_64__) && (defined(__clang__) || defined(__GNUC__))
#define CONTOURTTY_X86_AVX2_TARGET __attribute__((target("avx2")))
#else
#define CONTOURTTY_X86_AVX2_TARGET
#endif

double sampleClamped(const LuminanceField& field, int x, int y) {
  const int clamped_x = std::min(std::max(x, 0), field.width - 1);
  const int clamped_y = std::min(std::max(y, 0), field.height - 1);
  return field.values[static_cast<std::size_t>(clamped_y) * static_cast<std::size_t>(field.width) + static_cast<std::size_t>(clamped_x)];
}

Gradient sobelScalarPixel(const LuminanceField& field, int x, int y) {
  const double gx =
    -sampleClamped(field, x - 1, y - 1) + sampleClamped(field, x + 1, y - 1) -
    2.0 * sampleClamped(field, x - 1, y) + 2.0 * sampleClamped(field, x + 1, y) -
    sampleClamped(field, x - 1, y + 1) + sampleClamped(field, x + 1, y + 1);
  const double gy =
    -sampleClamped(field, x - 1, y - 1) - 2.0 * sampleClamped(field, x, y - 1) - sampleClamped(field, x + 1, y - 1) +
    sampleClamped(field, x - 1, y + 1) + 2.0 * sampleClamped(field, x, y + 1) + sampleClamped(field, x + 1, y + 1);
  return Gradient{.gx = gx, .gy = gy};
}

void storeSobelPixel(GradientField* gradients, int width, int x, int y, double gx, double gy) {
  gradients->values[static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x)] = Gradient{.gx = gx, .gy = gy};
}

void computeSobelScalarRow(const LuminanceField& field, int y, GradientField* gradients) {
  for (int x = 0; x < field.width; ++x) {
    const Gradient gradient = sobelScalarPixel(field, x, y);
    storeSobelPixel(gradients, field.width, x, y, gradient.gx, gradient.gy);
  }
}

#if defined(__aarch64__) && defined(__ARM_NEON)
void computeSobelNeonRow(const LuminanceField& field, int y, GradientField* gradients) {
  if (field.width < 3 || y == 0 || y == field.height - 1) {
    computeSobelScalarRow(field, y, gradients);
    return;
  }

  const std::size_t width = static_cast<std::size_t>(field.width);
  const double* previous = field.values.data() + static_cast<std::size_t>(y - 1) * width;
  const double* current = field.values.data() + static_cast<std::size_t>(y) * width;
  const double* next = field.values.data() + static_cast<std::size_t>(y + 1) * width;
  Gradient edge = sobelScalarPixel(field, 0, y);
  storeSobelPixel(gradients, field.width, 0, y, edge.gx, edge.gy);

  int x = 1;
  const int vector_end = field.width - 1 - ((field.width - 2) % 2);
  for (; x < vector_end; x += 2) {
    const float64x2_t top_left = vld1q_f64(previous + x - 1);
    const float64x2_t top_center = vld1q_f64(previous + x);
    const float64x2_t top_right = vld1q_f64(previous + x + 1);
    const float64x2_t middle_left = vld1q_f64(current + x - 1);
    const float64x2_t middle_right = vld1q_f64(current + x + 1);
    const float64x2_t bottom_left = vld1q_f64(next + x - 1);
    const float64x2_t bottom_center = vld1q_f64(next + x);
    const float64x2_t bottom_right = vld1q_f64(next + x + 1);
    float64x2_t gx = vsubq_f64(vnegq_f64(top_left), vnegq_f64(top_right));
    gx = vsubq_f64(gx, vaddq_f64(middle_left, middle_left));
    gx = vaddq_f64(gx, vaddq_f64(middle_right, middle_right));
    gx = vsubq_f64(gx, bottom_left);
    gx = vaddq_f64(gx, bottom_right);
    float64x2_t gy = vsubq_f64(vnegq_f64(top_left), vaddq_f64(top_center, top_center));
    gy = vsubq_f64(gy, top_right);
    gy = vaddq_f64(gy, bottom_left);
    gy = vaddq_f64(gy, vaddq_f64(bottom_center, bottom_center));
    gy = vaddq_f64(gy, bottom_right);
    double gx_values[2];
    double gy_values[2];
    vst1q_f64(gx_values, gx);
    vst1q_f64(gy_values, gy);
    storeSobelPixel(gradients, field.width, x, y, gx_values[0], gy_values[0]);
    storeSobelPixel(gradients, field.width, x + 1, y, gx_values[1], gy_values[1]);
  }
  for (; x < field.width - 1; ++x) {
    const Gradient gradient = sobelScalarPixel(field, x, y);
    storeSobelPixel(gradients, field.width, x, y, gradient.gx, gradient.gy);
  }

  edge = sobelScalarPixel(field, field.width - 1, y);
  storeSobelPixel(gradients, field.width, field.width - 1, y, edge.gx, edge.gy);
}
#endif

#if defined(__x86_64__) && (defined(__clang__) || defined(__GNUC__))
bool avx2Available() {
  return __builtin_cpu_supports("avx2");
}

CONTOURTTY_X86_AVX2_TARGET void computeSobelAvx2Row(const LuminanceField& field, int y, GradientField* gradients) {
  if (field.width < 5 || y == 0 || y == field.height - 1) {
    computeSobelScalarRow(field, y, gradients);
    return;
  }

  const std::size_t width = static_cast<std::size_t>(field.width);
  const double* previous = field.values.data() + static_cast<std::size_t>(y - 1) * width;
  const double* current = field.values.data() + static_cast<std::size_t>(y) * width;
  const double* next = field.values.data() + static_cast<std::size_t>(y + 1) * width;
  Gradient edge = sobelScalarPixel(field, 0, y);
  storeSobelPixel(gradients, field.width, 0, y, edge.gx, edge.gy);

  int x = 1;
  const int vector_end = field.width - 1 - ((field.width - 2) % 4);
  for (; x < vector_end; x += 4) {
    const __m256d top_left = _mm256_loadu_pd(previous + x - 1);
    const __m256d top_center = _mm256_loadu_pd(previous + x);
    const __m256d top_right = _mm256_loadu_pd(previous + x + 1);
    const __m256d middle_left = _mm256_loadu_pd(current + x - 1);
    const __m256d middle_right = _mm256_loadu_pd(current + x + 1);
    const __m256d bottom_left = _mm256_loadu_pd(next + x - 1);
    const __m256d bottom_center = _mm256_loadu_pd(next + x);
    const __m256d bottom_right = _mm256_loadu_pd(next + x + 1);
    __m256d gx = _mm256_sub_pd(_mm256_sub_pd(_mm256_setzero_pd(), top_left), _mm256_sub_pd(_mm256_setzero_pd(), top_right));
    gx = _mm256_sub_pd(gx, _mm256_add_pd(middle_left, middle_left));
    gx = _mm256_add_pd(gx, _mm256_add_pd(middle_right, middle_right));
    gx = _mm256_sub_pd(gx, bottom_left);
    gx = _mm256_add_pd(gx, bottom_right);
    __m256d gy = _mm256_sub_pd(_mm256_sub_pd(_mm256_setzero_pd(), top_left), _mm256_add_pd(top_center, top_center));
    gy = _mm256_sub_pd(gy, top_right);
    gy = _mm256_add_pd(gy, bottom_left);
    gy = _mm256_add_pd(gy, _mm256_add_pd(bottom_center, bottom_center));
    gy = _mm256_add_pd(gy, bottom_right);
    double gx_values[4];
    double gy_values[4];
    _mm256_storeu_pd(gx_values, gx);
    _mm256_storeu_pd(gy_values, gy);
    for (int lane = 0; lane < 4; ++lane) {
      storeSobelPixel(gradients, field.width, x + lane, y, gx_values[lane], gy_values[lane]);
    }
  }
  for (; x < field.width - 1; ++x) {
    const Gradient gradient = sobelScalarPixel(field, x, y);
    storeSobelPixel(gradients, field.width, x, y, gradient.gx, gradient.gy);
  }

  edge = sobelScalarPixel(field, field.width - 1, y);
  storeSobelPixel(gradients, field.width, field.width - 1, y, edge.gx, edge.gy);
}
#endif

void computeSobelRow(const LuminanceField& field, int y, GradientField* gradients) {
#if defined(__aarch64__) && defined(__ARM_NEON)
  computeSobelNeonRow(field, y, gradients);
#elif defined(__x86_64__) && (defined(__clang__) || defined(__GNUC__))
  if (avx2Available()) {
    computeSobelAvx2Row(field, y, gradients);
  } else {
    computeSobelScalarRow(field, y, gradients);
  }
#else
  computeSobelScalarRow(field, y, gradients);
#endif
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

std::vector<double> gaussianKernel(double sigma) {
  if (sigma <= 0.0) {
    throw std::invalid_argument("gaussian sigma must be positive");
  }
  const int radius = std::max(1, static_cast<int>(std::ceil(sigma * 3.0)));
  std::vector<double> kernel;
  kernel.reserve(static_cast<std::size_t>(radius * 2 + 1));
  double sum = 0.0;
  for (int i = -radius; i <= radius; ++i) {
    const double value = std::exp(-(static_cast<double>(i * i)) / (2.0 * sigma * sigma));
    kernel.push_back(value);
    sum += value;
  }
  for (double& value : kernel) {
    value /= sum;
  }
  return kernel;
}

double angularDistance(double a, double b) {
  double delta = std::fmod(std::abs(a - b), 2.0 * kPi);
  if (delta > kPi) {
    delta = 2.0 * kPi - delta;
  }
  return delta;
}

bool isCornerLike(const CellGradient& gradient, double threshold) {
  const double min_energy = std::min(gradient.horizontal_energy, gradient.vertical_energy);
  const double max_energy = std::max(gradient.horizontal_energy, gradient.vertical_energy);
  if (min_energy <= threshold || max_energy <= 0.0) {
    return false;
  }
  return min_energy / max_energy >= 0.55 && gradient.magnitude < max_energy * 1.15;
}

}  // namespace

Gradient GradientField::at(int x, int y) const {
  if (x < 0 || y < 0 || x >= width || y >= height) {
    throw std::out_of_range("gradient field index out of range");
  }
  return values.at(static_cast<std::size_t>(y) * static_cast<std::size_t>(width) + static_cast<std::size_t>(x));
}

GradientField computeSobelGradients(const LuminanceField& field) {
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }

  GradientField gradients;
  gradients.width = field.width;
  gradients.height = field.height;
  gradients.values.assign(static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height), Gradient{});
  parallelRows(field.height, field.width * field.height, [&](int row_begin, int row_end) {
    for (int y = row_begin; y < row_end; ++y) {
      computeSobelRow(field, y, &gradients);
    }
  });
  return gradients;
}

LuminanceField gradientMagnitudeField(const GradientField& gradients, double threshold) {
  if (gradients.width <= 0 || gradients.height <= 0 ||
      gradients.values.size() != static_cast<std::size_t>(gradients.width) * static_cast<std::size_t>(gradients.height)) {
    throw std::invalid_argument("invalid gradient field");
  }
  if (threshold < 0.0) {
    throw std::invalid_argument("gradient magnitude threshold must be non-negative");
  }
  LuminanceField field;
  field.width = gradients.width;
  field.height = gradients.height;
  field.values.assign(gradients.values.size(), 0.0);
  parallelRows(gradients.height, gradients.width * gradients.height, [&](int row_begin, int row_end) {
    for (int y = row_begin; y < row_end; ++y) {
      for (int x = 0; x < gradients.width; ++x) {
        const std::size_t index = static_cast<std::size_t>(y) * static_cast<std::size_t>(gradients.width) + static_cast<std::size_t>(x);
        const Gradient gradient = gradients.values[index];
        const double magnitude = std::hypot(gradient.gx, gradient.gy);
        field.values[index] = magnitude > threshold ? magnitude : 0.0;
      }
    }
  });
  return field;
}

LuminanceField gaussianBlur(const LuminanceField& field, double sigma) {
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }
  const std::vector<double> kernel = gaussianKernel(sigma);
  const int radius = static_cast<int>(kernel.size() / 2);

  LuminanceField horizontal;
  horizontal.width = field.width;
  horizontal.height = field.height;
  horizontal.values.assign(field.values.size(), 0.0);
  parallelRows(field.height, field.width * field.height, [&](int row_begin, int row_end) {
    for (int y = row_begin; y < row_end; ++y) {
      for (int x = 0; x < field.width; ++x) {
        double sum = 0.0;
        for (int k = -radius; k <= radius; ++k) {
          sum += sampleClamped(field, x + k, y) * kernel[static_cast<std::size_t>(k + radius)];
        }
        horizontal.values[static_cast<std::size_t>(y) * static_cast<std::size_t>(field.width) + static_cast<std::size_t>(x)] = sum;
      }
    }
  });

  LuminanceField output;
  output.width = field.width;
  output.height = field.height;
  output.values.assign(field.values.size(), 0.0);
  parallelRows(field.height, field.width * field.height, [&](int row_begin, int row_end) {
    for (int y = row_begin; y < row_end; ++y) {
      for (int x = 0; x < field.width; ++x) {
        double sum = 0.0;
        for (int k = -radius; k <= radius; ++k) {
          sum += sampleClamped(horizontal, x, y + k) * kernel[static_cast<std::size_t>(k + radius)];
        }
        output.values[static_cast<std::size_t>(y) * static_cast<std::size_t>(field.width) + static_cast<std::size_t>(x)] = sum;
      }
    }
  });
  return output;
}

LuminanceField differenceOfGaussians(const LuminanceField& field, DogOptions options) {
  if (!options.enabled()) {
    return field;
  }
  if (options.threshold < 0.0) {
    throw std::invalid_argument("DoG threshold must be non-negative");
  }
  const LuminanceField narrow = gaussianBlur(field, options.sigma1);
  const LuminanceField wide = gaussianBlur(field, options.sigma2);

  LuminanceField output;
  output.width = field.width;
  output.height = field.height;
  output.values.assign(field.values.size(), 0.0);
  parallelRows(field.height, field.width * field.height, [&](int row_begin, int row_end) {
    for (int y = row_begin; y < row_end; ++y) {
      for (int x = 0; x < field.width; ++x) {
        const std::size_t index = static_cast<std::size_t>(y) * static_cast<std::size_t>(field.width) + static_cast<std::size_t>(x);
        const double value = std::abs(narrow.values[index] - wide.values[index]);
        output.values[index] = value >= options.threshold ? value : 0.0;
      }
    }
  });
  return output;
}

LuminanceField applyStructureContrast(const LuminanceField& field, double amount) {
  if (field.width <= 0 || field.height <= 0 ||
      field.values.size() != static_cast<std::size_t>(field.width) * static_cast<std::size_t>(field.height)) {
    throw std::invalid_argument("invalid luminance field");
  }
  if (amount < 0.0) {
    throw std::invalid_argument("structure contrast must be non-negative");
  }
  if (amount == 0.0) {
    return field;
  }

  const double gain = 1.0 + amount;
  const int levels = std::clamp(static_cast<int>(std::lround(2.0 + amount * 6.0)), 2, 16);
  const double scale = static_cast<double>(levels - 1);
  LuminanceField output;
  output.width = field.width;
  output.height = field.height;
  output.values.assign(field.values.size(), 0.0);
  parallelRows(field.height, field.width * field.height, [&](int row_begin, int row_end) {
    for (int y = row_begin; y < row_end; ++y) {
      for (int x = 0; x < field.width; ++x) {
        const std::size_t index = static_cast<std::size_t>(y) * static_cast<std::size_t>(field.width) + static_cast<std::size_t>(x);
        const double contrasted = std::clamp((field.values[index] - 0.5) * gain + 0.5, 0.0, 1.0);
        output.values[index] = std::round(contrasted * scale) / scale;
      }
    }
  });
  return output;
}

CellGradient cellGradient(const GradientField& gradients, int cols, int rows, int col, int row) {
  if (gradients.width <= 0 || gradients.height <= 0 ||
      gradients.values.size() != static_cast<std::size_t>(gradients.width) * static_cast<std::size_t>(gradients.height)) {
    throw std::invalid_argument("invalid gradient field");
  }
  const SourceRegion region = cellSourceRegion(gradients.width, gradients.height, cols, rows, col, row);
  double gx = 0.0;
  double gy = 0.0;
  double horizontal_energy = 0.0;
  double vertical_energy = 0.0;
  int count = 0;
  for (int y = region.y0; y < region.y1; ++y) {
    for (int x = region.x0; x < region.x1; ++x) {
      const Gradient gradient = gradients.values[static_cast<std::size_t>(y) * static_cast<std::size_t>(gradients.width) + static_cast<std::size_t>(x)];
      gx += gradient.gx;
      gy += gradient.gy;
      horizontal_energy += std::abs(gradient.gx);
      vertical_energy += std::abs(gradient.gy);
      ++count;
    }
  }
  if (count > 0) {
    const double scale = 1.0 / static_cast<double>(count);
    gx *= scale;
    gy *= scale;
    horizontal_energy *= scale;
    vertical_energy *= scale;
  }
  return CellGradient{
    .gx = gx,
    .gy = gy,
    .magnitude = std::hypot(gx, gy),
    .orientation = std::atan2(gy, gx),
    .horizontal_energy = horizontal_energy,
    .vertical_energy = vertical_energy,
  };
}

std::optional<char32_t> directionalGlyphForGradient(const CellGradient& gradient, double threshold) {
  if (threshold < 0.0) {
    throw std::invalid_argument("edge threshold must be non-negative");
  }
  if (gradient.magnitude <= threshold) {
    return std::nullopt;
  }
  if (isCornerLike(gradient, threshold)) {
    return U'+';
  }

  struct Candidate {
    double angle;
    char32_t glyph;
  };
  const Candidate candidates[] = {
    Candidate{.angle = 0.0, .glyph = U'|'},
    Candidate{.angle = kPi, .glyph = U'|'},
    Candidate{.angle = -kPi, .glyph = U'|'},
    Candidate{.angle = kPi / 2.0, .glyph = gradient.gy >= 0.0 ? U'_' : U'-'},
    Candidate{.angle = -kPi / 2.0, .glyph = U'-'},
    Candidate{.angle = kPi / 4.0, .glyph = U'/'},
    Candidate{.angle = -3.0 * kPi / 4.0, .glyph = U'/'},
    Candidate{.angle = -kPi / 4.0, .glyph = U'\\'},
    Candidate{.angle = 3.0 * kPi / 4.0, .glyph = U'\\'},
  };

  const Candidate* best = &candidates[0];
  double best_distance = angularDistance(gradient.orientation, best->angle);
  for (const Candidate& candidate : candidates) {
    const double distance = angularDistance(gradient.orientation, candidate.angle);
    if (distance < best_distance) {
      best = &candidate;
      best_distance = distance;
    }
  }
  return best->glyph;
}

}  // namespace contourtty
