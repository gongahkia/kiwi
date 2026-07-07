#include "shader_compiler.hpp"
#include "shader_source.hpp"

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
#ifdef CONTOURTTY_SOURCE_DIR
  return CONTOURTTY_SOURCE_DIR;
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
  while (true) {
    const std::size_t colon = rest.find(':');
    const std::string_view entry = colon == std::string_view::npos ? rest : rest.substr(0, colon);
    if (!entry.empty()) {
      entries.emplace_back(entry);
    }
    if (colon == std::string_view::npos) {
      break;
    }
    rest.remove_prefix(colon + 1);
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

int processId() {
#ifdef _WIN32
  return _getpid();
#else
  return getpid();
#endif
}

class TempTree {
 public:
  TempTree() : path_(std::filesystem::temp_directory_path() / ("contourtty-shader-bundle-compile-" + std::to_string(processId()))) {
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
  contourtty::ShaderCompileOptions options;
  options.entry_point = "main";
  options.work_dir = temp.path();

  const auto shader_dir = sourceRoot() / "share" / "contourtty" / "shaders";
  const std::vector<std::string> bundled = {"noise.glsl", "plasma.glsl", "feedback.glsl", "sdf_room.glsl"};
  for (const std::string& name : bundled) {
    const std::string source = contourtty::loadShaderSource(shader_dir / name);
    const auto compiled = contourtty::compileShadertoyFragmentToSpirvAndMsl(source, options);
    expect(!compiled.spirv.empty(), "bundled shader produced SPIR-V");
    expect(!compiled.msl.empty(), "bundled shader produced MSL");
  }
}
