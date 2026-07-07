#include "shader_runtime.hpp"

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
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

int processId() {
#ifdef _WIN32
  return _getpid();
#else
  return getpid();
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

class TempTree {
 public:
  TempTree() : path_(std::filesystem::temp_directory_path() / ("contourtty-shader-runtime-" + std::to_string(processId()))) {
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

void writeShader(const std::filesystem::path& path, std::string_view rgb) {
  std::ofstream out(path);
  out << "void mainImage(out vec4 fragColor, in vec2 fragCoord) {\n"
      << "  fragColor = vec4(" << rgb << ", 1.0);\n"
      << "}\n";
}

bool firstPixelNear(const contourtty::Frame& frame, uint8_t r, uint8_t g, uint8_t b) {
  if (frame.rgb.size() < 3) {
    return false;
  }
  const auto near = [](uint8_t actual, uint8_t expected) {
    const int delta = static_cast<int>(actual) - static_cast<int>(expected);
    return delta >= -4 && delta <= 4;
  };
  return near(frame.rgb[0], r) && near(frame.rgb[1], g) && near(frame.rgb[2], b);
}

}  // namespace

int main() {
  if (!toolAvailable("glslangValidator") || !toolAvailable("spirv-cross")) {
    std::cout << "glslangValidator or spirv-cross unavailable; skipping shader runtime smoke\n";
    return 77;
  }
  if (!contourtty::shaderRuntimeAvailable()) {
    std::cout << "shader runtime unavailable; skipping shader runtime smoke\n";
    return 77;
  }

  TempTree temp;
  const auto shader_path = temp.path() / "runtime.glsl";
  writeShader(shader_path, "1.0, 0.0, 0.0");
  contourtty::ShaderFrameSource source(shader_path);
  const contourtty::Frame red = source.renderFrame(8, 4, 0, 0, 33333);
  expect(red.w == 8 && red.h == 4, "shader runtime dimensions");
  expect(firstPixelNear(red, 255, 0, 0), "shader runtime red frame");

  writeShader(shader_path, "0.0, 0.0, 1.0");
  std::filesystem::last_write_time(shader_path, std::filesystem::file_time_type::clock::now() + std::chrono::seconds(2));
  source.reloadIfChanged();
  const contourtty::Frame blue = source.renderFrame(8, 4, 33333, 1, 33333);
  expect(firstPixelNear(blue, 0, 0, 255), "shader runtime hot reload frame");
}
