#include "shader_compiler.hpp"
#include "shader_source.hpp"

#include <array>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

#ifdef _WIN32
#include <process.h>
#else
#include <unistd.h>
#endif

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

std::filesystem::path sourceRoot() {
#ifdef STROK_SOURCE_DIR
  return STROK_SOURCE_DIR;
#else
  return std::filesystem::current_path();
#endif
}

std::vector<std::filesystem::path> pathEntries() {
  std::vector<std::filesystem::path> entries;
  const char* path = std::getenv("PATH");
  if (path == nullptr) {
    return entries;
  }
  std::string_view rest(path);
  constexpr char delimiter =
#ifdef _WIN32
    ';';
#else
    ':';
#endif
  while (true) {
    const std::size_t split = rest.find(delimiter);
    const std::string_view entry = split == std::string_view::npos ? rest : rest.substr(0, split);
    if (!entry.empty()) {
      entries.emplace_back(entry);
    }
    if (split == std::string_view::npos) {
      break;
    }
    rest.remove_prefix(split + 1);
  }
  return entries;
}

bool toolAvailable(std::string_view name) {
  for (const auto& entry : pathEntries()) {
    std::error_code ec;
    auto candidate = entry / std::string(name);
#ifdef _WIN32
    if (!std::filesystem::exists(candidate, ec)) {
      candidate += ".exe";
    }
    if (std::filesystem::is_regular_file(candidate, ec)) {
#else
    if (std::filesystem::exists(candidate, ec) && access(candidate.c_str(), X_OK) == 0) {
#endif
      return true;
    }
  }
  return false;
}

bool hasSpirvMagic(const std::vector<std::uint8_t>& spirv) {
  constexpr std::array<std::uint8_t, 4> little_endian_magic {0x03, 0x02, 0x23, 0x07};
  constexpr std::array<std::uint8_t, 4> big_endian_magic {0x07, 0x23, 0x02, 0x03};
  if (spirv.size() < little_endian_magic.size()) {
    return false;
  }
  const std::array<std::uint8_t, 4> prefix {spirv[0], spirv[1], spirv[2], spirv[3]};
  return prefix == little_endian_magic || prefix == big_endian_magic;
}

int processId() {
#ifdef _WIN32
  return _getpid();
#else
  return getpid();
#endif
}

class TempTree {
 public:
  TempTree() : path_(std::filesystem::temp_directory_path() / ("strok-shader-bundle-compile-" + std::to_string(processId()))) {
    std::filesystem::remove_all(path_);
    std::filesystem::create_directories(path_);
  }

  ~TempTree() {
    std::error_code ec;
    std::filesystem::remove_all(path_, ec);
  }

  const std::filesystem::path& path() const noexcept {
    return path_;
  }

 private:
  std::filesystem::path path_;
};

}  // namespace

int main() {
  if (!toolAvailable("glslangValidator") || !toolAvailable("spirv-cross")) {
    std::cout << "glslangValidator or spirv-cross unavailable; skipping bundled shader compile smoke\n";
    return 77;
  }

  TempTree temp;
  strok::ShaderCompileOptions options;
  options.entry_point = "main";
  options.work_dir = temp.path();

  const auto shader_dir = sourceRoot() / "share" / "strok" / "shaders";
  const std::vector<std::string> bundled = {"noise.glsl", "plasma.glsl", "feedback.glsl", "sdf_room.glsl"};
  for (const std::string& name : bundled) {
    const std::string source = strok::loadShaderSource(shader_dir / name);
    const auto compiled = strok::compileShadertoyFragmentToSpirvAndMsl(source, options);
    expect(!compiled.spirv.empty(), "bundled shader produced SPIR-V");
    expect(hasSpirvMagic(compiled.spirv), "bundled shader produced SPIR-V magic");
    expect(!compiled.msl.empty(), "bundled shader produced MSL");
    const auto repeated = strok::compileShadertoyFragmentToSpirvAndMsl(source, options);
    expect(repeated.spirv == compiled.spirv, "bundled shader SPIR-V is deterministic");
    expect(repeated.msl == compiled.msl, "bundled shader MSL is deterministic");
  }
}
