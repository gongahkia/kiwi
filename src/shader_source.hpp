#pragma once

#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>

namespace contourtty {

class ShaderSourceError : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

bool isShaderSourcePath(const std::filesystem::path& path);
bool isShadertoySource(std::string_view source) noexcept;
std::string loadShaderSource(const std::filesystem::path& path);
std::string wrapShadertoyFragmentShader(std::string_view source);

}  // namespace contourtty
