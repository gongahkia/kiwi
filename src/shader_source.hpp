#pragma once

#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>

namespace strok {

class ShaderSourceError : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

bool isShaderSourcePath(const std::filesystem::path& path);
std::optional<std::filesystem::path> resolveBundledShader(std::string_view input);
bool isShadertoySource(std::string_view source) noexcept;
std::string loadShaderSource(const std::filesystem::path& path);
std::string wrapShadertoyFragmentShader(std::string_view source);

}  // namespace strok
