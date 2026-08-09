#include "c_api_config.hpp"

#include "../include/strok/renderer.hpp"

#include <exception>
#include <memory>
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

void STROK_C_CALL strok_renderer_destroy(StrokRenderer* renderer) {
  delete renderer;
}

const char* STROK_C_CALL strok_last_error_message(void) {
  return last_error.c_str();
}

}  // extern "C"
