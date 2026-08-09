#include "c_api_config.hpp"

#include "color_image_view.hpp"
#include "depth_image_view.hpp"
#include "normal_image_view.hpp"
#include "render_input.hpp"

#include "../include/strok/renderer.hpp"

#include <cstddef>
#include <cstdint>
#include <exception>
#include <limits>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

struct StrokRenderer {
  std::unique_ptr<strok::Renderer> renderer;
};

namespace {

thread_local std::string last_error;

void setLastError(std::string_view message) noexcept {
  try {
    last_error.assign(message);
  } catch (...) {
    last_error.clear();
  }
}

void clearLastError() noexcept {
  last_error.clear();
}

StrokStatus failure(StrokStatus status, std::string_view message) noexcept {
  setLastError(message);
  return status;
}

StrokStatus statusFromResult(const strok::RenderResult& result) noexcept {
  switch (result.status) {
    case strok::RenderStatus::Success:
      return STROK_STATUS_SUCCESS;
    case strok::RenderStatus::BackendFallback:
      return STROK_STATUS_BACKEND_FALLBACK;
    case strok::RenderStatus::InvalidInput:
      return STROK_STATUS_INVALID_INPUT;
    case strok::RenderStatus::InvalidConfiguration:
      return STROK_STATUS_INVALID_CONFIGURATION;
    case strok::RenderStatus::InternalError:
      return STROK_STATUS_INTERNAL_ERROR;
  }
  return STROK_STATUS_INTERNAL_ERROR;
}

std::optional<strok::ColorPixelFormat> colorPixelFormatFromC(StrokColorPixelFormat pixel_format) {
  switch (pixel_format) {
    case STROK_COLOR_PIXEL_FORMAT_RGB24:
      return strok::ColorPixelFormat::Rgb24;
    case STROK_COLOR_PIXEL_FORMAT_RGBA8:
      return strok::ColorPixelFormat::Rgba8;
    case STROK_COLOR_PIXEL_FORMAT_BGRA8:
      return strok::ColorPixelFormat::Bgra8;
  }
  return std::nullopt;
}

std::optional<strok::ColorImageView> colorImageViewFromC(const StrokColorImageView* image,
                                                          std::string* error) {
  if (image == nullptr) {
    if (error != nullptr) {
      *error = "color image view is required";
    }
    return std::nullopt;
  }
  if ((image->version >> 16U) != STROK_C_ABI_VERSION_MAJOR) {
    if (error != nullptr) {
      *error = "unsupported color image C ABI major version";
    }
    return std::nullopt;
  }
  if (image->struct_size < sizeof(*image)) {
    if (error != nullptr) {
      *error = "color image C ABI structure is smaller than the required layout";
    }
    return std::nullopt;
  }
  if (image->row_stride_bytes > std::numeric_limits<std::size_t>::max()) {
    if (error != nullptr) {
      *error = "color image row stride is not representable";
    }
    return std::nullopt;
  }
  const std::optional<strok::ColorPixelFormat> pixel_format = colorPixelFormatFromC(image->pixel_format);
  if (!pixel_format.has_value()) {
    if (error != nullptr) {
      *error = "color image pixel format is unsupported";
    }
    return std::nullopt;
  }
  const strok::ColorImageView result{
    .data = image->data,
    .width = image->width,
    .height = image->height,
    .row_stride_bytes = static_cast<std::size_t>(image->row_stride_bytes),
    .pixel_format = *pixel_format,
  };
  if (const std::optional<std::string> validation_error = strok::colorImageViewError(result); validation_error.has_value()) {
    if (error != nullptr) {
      *error = *validation_error;
    }
    return std::nullopt;
  }
  return result;
}

std::optional<strok::DepthImageView> depthImageViewFromC(const StrokDepthImageView* image,
                                                          std::string* error) {
  if (image == nullptr || (image->version >> 16U) != STROK_C_ABI_VERSION_MAJOR ||
      image->struct_size < sizeof(*image) || image->row_stride_bytes > std::numeric_limits<std::size_t>::max() ||
      image->pixel_format != STROK_DEPTH_PIXEL_FORMAT_FLOAT64 ||
      image->interpretation != STROK_DEPTH_INTERPRETATION_CAMERA_LINEAR) {
    if (error != nullptr) {
      *error = "depth image C ABI view is invalid";
    }
    return std::nullopt;
  }
  const strok::DepthImageView result{
    .data = image->data,
    .width = image->width,
    .height = image->height,
    .row_stride_bytes = static_cast<std::size_t>(image->row_stride_bytes),
  };
  if (const std::optional<std::string> validation_error = strok::depthImageViewError(result); validation_error.has_value()) {
    if (error != nullptr) {
      *error = *validation_error;
    }
    return std::nullopt;
  }
  return result;
}

std::optional<strok::NormalImageView> normalImageViewFromC(const StrokNormalImageView* image,
                                                            std::string* error) {
  if (image == nullptr || (image->version >> 16U) != STROK_C_ABI_VERSION_MAJOR ||
      image->struct_size < sizeof(*image) || image->row_stride_bytes > std::numeric_limits<std::size_t>::max() ||
      image->pixel_format != STROK_NORMAL_PIXEL_FORMAT_FLOAT64X3 || image->space != STROK_NORMAL_SPACE_VIEW) {
    if (error != nullptr) {
      *error = "normal image C ABI view is invalid";
    }
    return std::nullopt;
  }
  const strok::NormalImageView result{
    .data = image->data,
    .width = image->width,
    .height = image->height,
    .row_stride_bytes = static_cast<std::size_t>(image->row_stride_bytes),
  };
  if (const std::optional<std::string> validation_error = strok::normalImageViewError(result); validation_error.has_value()) {
    if (error != nullptr) {
      *error = *validation_error;
    }
    return std::nullopt;
  }
  return result;
}

std::optional<strok::RenderInput> renderInputFromC(const StrokRenderInput* input, std::string* error) {
  if (input == nullptr || (input->version >> 16U) != STROK_C_ABI_VERSION_MAJOR || input->struct_size < sizeof(*input)) {
    if (error != nullptr) {
      *error = "render input C ABI view is invalid";
    }
    return std::nullopt;
  }
  const std::optional<strok::ColorImageView> color = colorImageViewFromC(input->color, error);
  if (!color.has_value()) {
    return std::nullopt;
  }
  strok::RenderInput result{.color = *color};
  if (input->depth != nullptr) {
    const std::optional<strok::DepthImageView> depth = depthImageViewFromC(input->depth, error);
    if (!depth.has_value()) {
      return std::nullopt;
    }
    result.depth = *depth;
  }
  if (input->normals != nullptr) {
    const std::optional<strok::NormalImageView> normals = normalImageViewFromC(input->normals, error);
    if (!normals.has_value()) {
      return std::nullopt;
    }
    result.normals = *normals;
  }
  if (const std::optional<std::string> validation_error = strok::renderInputError(result); validation_error.has_value()) {
    if (error != nullptr) {
      *error = *validation_error;
    }
    return std::nullopt;
  }
  return result;
}

}  // namespace

extern "C" {

StrokStatus STROK_C_CALL strok_renderer_create(const StrokRendererConfig* config,
                                                const StrokRenderGrid* grid,
                                                StrokRenderer** out_renderer) {
  if (out_renderer == nullptr) {
    return failure(STROK_STATUS_INVALID_ARGUMENT, "renderer output handle is required");
  }
  *out_renderer = nullptr;
  try {
    std::string error;
    std::optional<strok::RendererConfig> renderer_config = strok::rendererConfigFromC(config, &error);
    if (!renderer_config.has_value()) {
      return failure(STROK_STATUS_INVALID_ARGUMENT, error);
    }
    std::optional<strok::RenderGrid> renderer_grid = strok::renderGridFromC(grid, &error);
    if (!renderer_grid.has_value()) {
      return failure(STROK_STATUS_INVALID_ARGUMENT, error);
    }

    strok::Renderer::CreateResult created = strok::Renderer::create(std::move(*renderer_config), *renderer_grid);
    if (!created.succeeded()) {
      return failure(statusFromResult(created.result), created.result.message);
    }
    std::unique_ptr<StrokRenderer> handle(new StrokRenderer{.renderer = std::move(created.renderer)});
    *out_renderer = handle.release();
    clearLastError();
    return STROK_STATUS_SUCCESS;
  } catch (const std::exception& error) {
    return failure(STROK_STATUS_INTERNAL_ERROR, error.what());
  } catch (...) {
    return failure(STROK_STATUS_INTERNAL_ERROR, "unexpected renderer creation failure");
  }
}

StrokStatus STROK_C_CALL strok_renderer_reset(StrokRenderer* renderer) {
  if (renderer == nullptr || renderer->renderer == nullptr) {
    return failure(STROK_STATUS_INVALID_ARGUMENT, "renderer handle is required");
  }
  try {
    renderer->renderer->reset();
    clearLastError();
    return STROK_STATUS_SUCCESS;
  } catch (const std::exception& error) {
    return failure(STROK_STATUS_INTERNAL_ERROR, error.what());
  } catch (...) {
    return failure(STROK_STATUS_INTERNAL_ERROR, "unexpected renderer reset failure");
  }
}

void STROK_C_CALL strok_color_image_view_init(StrokColorImageView* image) {
  if (image == nullptr) {
    return;
  }
  *image = StrokColorImageView{
    .version = STROK_C_ABI_VERSION,
    .struct_size = sizeof(StrokColorImageView),
    .pixel_format = STROK_COLOR_PIXEL_FORMAT_RGB24,
  };
}

void STROK_C_CALL strok_depth_image_view_init(StrokDepthImageView* image) {
  if (image != nullptr) {
    *image = StrokDepthImageView{.version = STROK_C_ABI_VERSION,
                                  .struct_size = sizeof(StrokDepthImageView),
                                  .pixel_format = STROK_DEPTH_PIXEL_FORMAT_FLOAT64,
                                  .interpretation = STROK_DEPTH_INTERPRETATION_CAMERA_LINEAR};
  }
}

void STROK_C_CALL strok_normal_image_view_init(StrokNormalImageView* image) {
  if (image != nullptr) {
    *image = StrokNormalImageView{.version = STROK_C_ABI_VERSION,
                                   .struct_size = sizeof(StrokNormalImageView),
                                   .pixel_format = STROK_NORMAL_PIXEL_FORMAT_FLOAT64X3,
                                   .space = STROK_NORMAL_SPACE_VIEW};
  }
}

void STROK_C_CALL strok_render_input_init(StrokRenderInput* input) {
  if (input != nullptr) {
    *input = StrokRenderInput{.version = STROK_C_ABI_VERSION, .struct_size = sizeof(StrokRenderInput)};
  }
}

StrokStatus STROK_C_CALL strok_renderer_render_color(StrokRenderer* renderer,
                                                       const StrokColorImageView* image) {
  if (renderer == nullptr || renderer->renderer == nullptr) {
    return failure(STROK_STATUS_INVALID_ARGUMENT, "renderer handle is required");
  }
  try {
    std::string error;
    const std::optional<strok::ColorImageView> color = colorImageViewFromC(image, &error);
    if (!color.has_value()) {
      return failure(STROK_STATUS_INVALID_ARGUMENT, error);
    }
    const strok::RenderResult result = renderer->renderer->render(*color);
    if (!result.succeeded()) {
      return failure(statusFromResult(result), result.message);
    }
    clearLastError();
    return statusFromResult(result);
  } catch (const std::exception& error) {
    return failure(STROK_STATUS_INTERNAL_ERROR, error.what());
  } catch (...) {
    return failure(STROK_STATUS_INTERNAL_ERROR, "unexpected color render failure");
  }
}

StrokStatus STROK_C_CALL strok_renderer_render_input(StrokRenderer* renderer,
                                                       const StrokRenderInput* input) {
  if (renderer == nullptr || renderer->renderer == nullptr) {
    return failure(STROK_STATUS_INVALID_ARGUMENT, "renderer handle is required");
  }
  try {
    std::string error;
    const std::optional<strok::RenderInput> render_input = renderInputFromC(input, &error);
    if (!render_input.has_value()) {
      return failure(STROK_STATUS_INVALID_ARGUMENT, error);
    }
    const strok::RenderResult result = renderer->renderer->render(*render_input);
    if (!result.succeeded()) {
      return failure(statusFromResult(result), result.message);
    }
    clearLastError();
    return statusFromResult(result);
  } catch (const std::exception& error) {
    return failure(STROK_STATUS_INTERNAL_ERROR, error.what());
  } catch (...) {
    return failure(STROK_STATUS_INTERNAL_ERROR, "unexpected rich input render failure");
  }
}

void STROK_C_CALL strok_renderer_destroy(StrokRenderer* renderer) {
  delete renderer;
}

const char* STROK_C_CALL strok_last_error_message(void) {
  return last_error.c_str();
}

}  // extern "C"
