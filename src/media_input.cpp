#include "media_input.hpp"

namespace strok {

std::optional<CameraInputSpec> cameraInputSpec(std::string_view input) {
  if (input.starts_with("avfoundation:")) {
    return CameraInputSpec{.format = "avfoundation", .device = std::string(input.substr(13))};
  }
  if (input.starts_with("v4l2:")) {
    return CameraInputSpec{.format = "v4l2", .device = std::string(input.substr(5))};
  }
  if (input.starts_with("dshow:")) {
    return CameraInputSpec{.format = "dshow", .device = std::string(input.substr(6))};
  }
  if (input.starts_with("/dev/video")) {
    return CameraInputSpec{.format = "v4l2", .device = std::string(input)};
  }
  if (input != "cam" && input != "camera") {
    return std::nullopt;
  }
#if defined(__APPLE__)
  return CameraInputSpec{.format = "avfoundation", .device = "0"};
#elif defined(__linux__)
  return CameraInputSpec{.format = "v4l2", .device = "/dev/video0"};
#elif defined(_WIN32)
  return CameraInputSpec{.format = "dshow", .device = "video=default"};
#else
  return std::nullopt;
#endif
}

bool isCameraInput(std::string_view input) noexcept {
  return cameraInputSpec(input).has_value();
}

}  // namespace strok
