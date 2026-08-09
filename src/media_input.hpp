#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace strok {

struct CameraInputSpec {
  std::string format;
  std::string device;
};

std::optional<CameraInputSpec> cameraInputSpec(std::string_view input);
bool isCameraInput(std::string_view input) noexcept;
bool isRtspInput(std::string_view input) noexcept;
bool isLatencySensitiveInput(std::string_view input) noexcept;

}  // namespace strok
