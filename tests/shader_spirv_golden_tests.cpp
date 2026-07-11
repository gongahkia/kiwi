#include "shader_compiler.hpp"

#include <array>
#include <cstdio>
#include <cstdint>
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

class TempTree {
 public:
  TempTree() : path_(std::filesystem::temp_directory_path() / ("strok-shader-spirv-golden-" + std::to_string(processId()))) {
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

std::filesystem::path writeFile(const std::filesystem::path& path, std::string_view contents) {
  std::ofstream out(path);
  out << contents;
  return path;
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

std::string readCommandOutput(const char* command) {
#ifdef _WIN32
  FILE* pipe = _popen(command, "r");
#else
  FILE* pipe = popen(command, "r");
#endif
  if (pipe == nullptr) {
    return {};
  }
  std::string output;
  std::array<char, 256> buffer {};
  while (std::fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
    output += buffer.data();
  }
#ifdef _WIN32
  _pclose(pipe);
#else
  pclose(pipe);
#endif
  return output;
}

uint64_t fnv1a64(const std::vector<std::uint8_t>& bytes) {
  uint64_t hash = 14695981039346656037ULL;
  for (const std::uint8_t byte : bytes) {
    hash ^= byte;
    hash *= 1099511628211ULL;
  }
  return hash;
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

}  // namespace

int main() {
  if (!toolAvailable("glslangValidator")) {
    std::cout << "glslangValidator unavailable; skipping SPIR-V golden smoke\n";
    return 77;
  }
  const std::string version = readCommandOutput("glslangValidator --version");
  if (version.find("16.3.0") == std::string::npos) {
    std::cout << "glslangValidator version is not the pinned golden version; skipping SPIR-V golden smoke\n";
    return 77;
  }

  TempTree temp;
  const auto shader = writeFile(temp.path() / "golden.frag",
                                "#version 450\n"
                                "layout(location = 0) out vec4 fragColor;\n"
                                "void main() {\n"
                                "  fragColor = vec4(0.125, 0.25, 0.5, 1.0);\n"
                                "}\n");

  strok::ShaderCompileOptions options;
  options.entry_point = "main";
  options.work_dir = temp.path();
  const auto first = strok::compileGlslToSpirv(shader, options);
  const auto second = strok::compileGlslToSpirv(shader, options);

  expect(first == second, "fixed shader SPIR-V is deterministic");
  expect(hasSpirvMagic(first), "fixed shader SPIR-V magic");
  expect(first.size() == 384, "fixed shader SPIR-V byte size");
  expect(fnv1a64(first) == 0xa3e86c909a992e9bULL, "fixed shader SPIR-V golden hash");
}
