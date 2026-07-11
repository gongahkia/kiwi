#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace strok {

enum class ShaderStage {
  Vertex,
  Fragment,
  Compute,
};

struct ShaderToolchain {
  std::filesystem::path glslang_validator = "glslangValidator";
  std::filesystem::path spirv_cross = "spirv-cross";
};

struct ShaderCompileOptions {
  ShaderStage stage = ShaderStage::Fragment;
  std::string entry_point = "main";
  ShaderToolchain tools;
  std::optional<std::filesystem::path> work_dir;
};

struct ShaderCompileResult {
  std::vector<std::uint8_t> spirv;
  std::string msl;
};

class ShaderCompileError : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

std::string_view shaderStageFlag(ShaderStage stage) noexcept;
std::vector<std::uint8_t> compileGlslToSpirv(const std::filesystem::path& source, const ShaderCompileOptions& options = {});
std::vector<std::uint8_t> compileGlslSourceToSpirv(std::string_view source, const ShaderCompileOptions& options = {});
std::string compileSpirvToMsl(std::span<const std::uint8_t> spirv, const ShaderCompileOptions& options = {});
ShaderCompileResult compileGlslToSpirvAndMsl(const std::filesystem::path& source, const ShaderCompileOptions& options = {});
ShaderCompileResult compileShadertoyFragmentToSpirvAndMsl(std::string_view source, const ShaderCompileOptions& options = {});

}  // namespace strok
