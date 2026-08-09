#pragma once

#include "../include/strok/motion_vector_view.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstring>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace strok {

struct MotionVectorSample {
  float x = 0.0F;
  float y = 0.0F;
};

inline std::optional<std::string> motionVectorViewError(const MotionVectorView& image) {
  if (image.data == nullptr) {
    return "motion vector data is required";
  }
  if (image.width <= 0 || image.height <= 0) {
    return "motion vector dimensions must be positive";
  }
  if (image.pixel_format != MotionVectorPixelFormat::Float32x2) {
    return "motion vector pixel format is unsupported";
  }
  if (image.direction != MotionVectorDirection::CurrentToPrevious) {
    return "motion vector direction is unsupported";
  }
  if (image.unit != MotionVectorUnit::SourcePixels) {
    return "motion vector unit is unsupported";
  }
  if (image.row_stride_bytes % sizeof(float) != 0U) {
    return "motion vector row stride must preserve Float32 alignment";
  }

  const std::size_t width = static_cast<std::size_t>(image.width);
  const std::size_t height = static_cast<std::size_t>(image.height);
  if (width > std::numeric_limits<std::size_t>::max() / height) {
    return "motion vector dimensions overflow";
  }
  constexpr std::size_t components_per_pixel = 2U;
  if (width > std::numeric_limits<std::size_t>::max() / (components_per_pixel * sizeof(float))) {
    return "motion vector row size overflows";
  }
  const std::size_t row_bytes = width * components_per_pixel * sizeof(float);
  if (image.row_stride_bytes < row_bytes) {
    return "motion vector row stride is smaller than Float32x2 row size";
  }

  const std::size_t rows_before_last = height - 1U;
  if (rows_before_last > 0 && image.row_stride_bytes > (std::numeric_limits<std::size_t>::max() - row_bytes) / rows_before_last) {
    return "motion vector layout overflows";
  }
  return std::nullopt;
}

inline MotionVectorSample motionVectorAt(const MotionVectorView& image, int x, int y) noexcept {
  const auto* row = reinterpret_cast<const unsigned char*>(image.data) + static_cast<std::size_t>(y) * image.row_stride_bytes;
  MotionVectorSample vector;
  const auto* pixel = row + static_cast<std::size_t>(x) * 2U * sizeof(float);
  std::memcpy(&vector.x, pixel, sizeof(vector.x));
  std::memcpy(&vector.y, pixel + sizeof(float), sizeof(vector.y));
  return vector;
}

inline bool motionVectorValidityDefined(MotionVectorValidity validity) noexcept {
  return validity == MotionVectorValidity::Valid ||
         validity == MotionVectorValidity::Invalid ||
         validity == MotionVectorValidity::Disoccluded;
}

inline std::optional<std::string> motionVectorValidityViewError(const MotionVectorValidityView& image) {
  if (image.data == nullptr) {
    return "motion vector validity data is required";
  }
  if (image.width <= 0 || image.height <= 0) {
    return "motion vector validity dimensions must be positive";
  }

  const std::size_t width = static_cast<std::size_t>(image.width);
  const std::size_t height = static_cast<std::size_t>(image.height);
  if (width > std::numeric_limits<std::size_t>::max() / height) {
    return "motion vector validity dimensions overflow";
  }
  if (image.row_stride_bytes < width) {
    return "motion vector validity row stride is smaller than byte row size";
  }

  const std::size_t rows_before_last = height - 1U;
  if (rows_before_last > 0 && image.row_stride_bytes > (std::numeric_limits<std::size_t>::max() - width) / rows_before_last) {
    return "motion vector validity layout overflows";
  }
  return std::nullopt;
}

inline MotionVectorValidity motionVectorValidityAt(const MotionVectorValidityView& image, int x, int y) noexcept {
  const auto* row = image.data + static_cast<std::size_t>(y) * image.row_stride_bytes;
  return static_cast<MotionVectorValidity>(row[x]);
}

struct CellMotionVector {
  // Previous-to-current cell displacement, matching FlowVector's warp convention.
  double dx = 0.0;
  double dy = 0.0;
  MotionVectorValidity validity = MotionVectorValidity::Invalid;
};

struct CellMotionField {
  int cols = 0;
  int rows = 0;
  std::vector<CellMotionVector> vectors;

  const CellMotionVector& at(int col, int row) const {
    if (col < 0 || row < 0 || col >= cols || row >= rows) {
      throw std::out_of_range("cell motion index out of range");
    }
    return vectors.at(static_cast<std::size_t>(row) * static_cast<std::size_t>(cols) + static_cast<std::size_t>(col));
  }
};

inline CellMotionField remapMotionVectorsToCellGrid(const MotionVectorView& motion_vectors,
                                                     const MotionVectorValidityView* validity,
                                                     int cols,
                                                     int rows) {
  if (const std::optional<std::string> error = motionVectorViewError(motion_vectors); error.has_value()) {
    throw std::invalid_argument(*error);
  }
  if (cols <= 0 || rows <= 0) {
    throw std::invalid_argument("cell motion dimensions must be positive");
  }
  if (validity != nullptr) {
    if (const std::optional<std::string> error = motionVectorValidityViewError(*validity); error.has_value()) {
      throw std::invalid_argument(*error);
    }
    if (validity->width != motion_vectors.width || validity->height != motion_vectors.height) {
      throw std::invalid_argument("motion vector validity dimensions must match motion vectors");
    }
    for (int y = 0; y < validity->height; ++y) {
      for (int x = 0; x < validity->width; ++x) {
        if (!motionVectorValidityDefined(motionVectorValidityAt(*validity, x, y))) {
          throw std::invalid_argument("motion vector validity contains an unsupported value");
        }
      }
    }
  }

  CellMotionField field;
  field.cols = cols;
  field.rows = rows;
  field.vectors.reserve(static_cast<std::size_t>(cols) * static_cast<std::size_t>(rows));
  for (int row = 0; row < rows; ++row) {
    const int source_y = std::min(static_cast<int>((static_cast<double>(row) + 0.5) * motion_vectors.height / rows), motion_vectors.height - 1);
    for (int col = 0; col < cols; ++col) {
      const int source_x = std::min(static_cast<int>((static_cast<double>(col) + 0.5) * motion_vectors.width / cols), motion_vectors.width - 1);
      const MotionVectorValidity sample_validity = validity == nullptr
                                                      ? MotionVectorValidity::Valid
                                                      : motionVectorValidityAt(*validity, source_x, source_y);
      if (sample_validity != MotionVectorValidity::Valid) {
        field.vectors.push_back(CellMotionVector{.validity = sample_validity});
        continue;
      }

      const MotionVectorSample vector = motionVectorAt(motion_vectors, source_x, source_y);
      const double previous_x = static_cast<double>(source_x) + static_cast<double>(vector.x);
      const double previous_y = static_cast<double>(source_y) + static_cast<double>(vector.y);
      if (!std::isfinite(vector.x) || !std::isfinite(vector.y) ||
          previous_x < 0.0 || previous_x >= motion_vectors.width ||
          previous_y < 0.0 || previous_y >= motion_vectors.height) {
        field.vectors.push_back(CellMotionVector{});
        continue;
      }
      field.vectors.push_back(CellMotionVector{
          .dx = -static_cast<double>(vector.x) * cols / motion_vectors.width,
          .dy = -static_cast<double>(vector.y) * rows / motion_vectors.height,
          .validity = MotionVectorValidity::Valid,
      });
    }
  }
  return field;
}

}  // namespace strok
