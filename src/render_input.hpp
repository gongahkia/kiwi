#pragma once

#include "../include/strok/render_input.hpp"

#include "color_image_view.hpp"
#include "depth_image_view.hpp"
#include "motion_vector_view.hpp"
#include "normal_image_view.hpp"

#include <optional>
#include <string>

namespace strok {

inline std::optional<std::string> renderInputError(const RenderInput& input) {
  if (const std::optional<std::string> error = colorImageViewError(input.color); error.has_value()) {
    return error;
  }
  if (input.depth.has_value()) {
    if (const std::optional<std::string> error = depthImageViewError(*input.depth); error.has_value()) {
      return error;
    }
    if (input.depth->width != input.color.width || input.depth->height != input.color.height) {
      return "depth image dimensions must match color image dimensions";
    }
  }
  if (input.normals.has_value()) {
    if (const std::optional<std::string> error = normalImageViewError(*input.normals); error.has_value()) {
      return error;
    }
    if (input.normals->width != input.color.width || input.normals->height != input.color.height) {
      return "normal image dimensions must match color image dimensions";
    }
  }
  if (input.lookahead_color.has_value()) {
    if (const std::optional<std::string> error = colorImageViewError(*input.lookahead_color); error.has_value()) {
      return error;
    }
    if (input.lookahead_color->width != input.color.width || input.lookahead_color->height != input.color.height) {
      return "lookahead color image dimensions must match color image dimensions";
    }
  }
  if (input.motion_vectors.has_value()) {
    if (const std::optional<std::string> error = motionVectorViewError(*input.motion_vectors); error.has_value()) {
      return error;
    }
    if (input.motion_vectors->width != input.color.width || input.motion_vectors->height != input.color.height) {
      return "motion vector dimensions must match color image dimensions";
    }
  }
  if (input.motion_vector_validity.has_value()) {
    if (!input.motion_vectors.has_value()) {
      return "motion vector validity requires motion vectors";
    }
    if (const std::optional<std::string> error = motionVectorValidityViewError(*input.motion_vector_validity); error.has_value()) {
      return error;
    }
    if (input.motion_vector_validity->width != input.color.width || input.motion_vector_validity->height != input.color.height) {
      return "motion vector validity dimensions must match color image dimensions";
    }
    for (int y = 0; y < input.motion_vector_validity->height; ++y) {
      for (int x = 0; x < input.motion_vector_validity->width; ++x) {
        if (!motionVectorValidityDefined(motionVectorValidityAt(*input.motion_vector_validity, x, y))) {
          return "motion vector validity contains an unsupported value";
        }
      }
    }
  }
  return std::nullopt;
}

}  // namespace strok
