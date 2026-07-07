#include "shader_compiler.hpp"

#include <cstdlib>
#include <filesystem>
#include <functional>
#include <fstream>
#include <sstream>
#include <iostream>
#include <stdexcept>
#include <string>

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
  TempTree() : path_(std::filesystem::temp_directory_path() / ("contourtty-shader-test-" + std::to_string(processId()))) {
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

std::filesystem::path writeFile(const std::filesystem::path& path, const std::string& contents) {
  {
    std::ofstream out(path);
    out << contents;
  }
  return path;
}

std::string readFile(const std::filesystem::path& path) {
  std::ifstream input(path);
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

std::filesystem::path fakeGlslang() {
#ifdef CONTOURTTY_FAKE_GLSLANG
  return CONTOURTTY_FAKE_GLSLANG;
#else
  return "fake-glslangValidator";
#endif
}

std::filesystem::path fakeSpirvCross() {
#ifdef CONTOURTTY_FAKE_SPIRV_CROSS
  return CONTOURTTY_FAKE_SPIRV_CROSS;
#else
  return "fake-spirv-cross";
#endif
}

bool throwsShaderError(const std::function<void()>& body) {
  try {
    body();
  } catch (const contourtty::ShaderCompileError&) {
    return true;
  }
  return false;
}

void setEnvPath(const char* name, const std::filesystem::path& path) {
#ifdef _WIN32
  _putenv_s(name, path.string().c_str());
#else
  setenv(name, path.c_str(), 1);
#endif
}

void unsetEnv(const char* name) {
#ifdef _WIN32
  _putenv_s(name, "");
#else
  unsetenv(name);
#endif
}

}  // namespace

int main() {
  expect(contourtty::shaderStageFlag(contourtty::ShaderStage::Vertex) == "vert", "vertex stage flag");
  expect(contourtty::shaderStageFlag(contourtty::ShaderStage::Fragment) == "frag", "fragment stage flag");
  expect(contourtty::shaderStageFlag(contourtty::ShaderStage::Compute) == "comp", "compute stage flag");

  TempTree temp;
  const auto shader = writeFile(temp.path() / "shader.glsl",
                                "#version 450\n"
                                "layout(location = 0) out vec4 fragColor;\n"
                                "void mainImage() { fragColor = vec4(1.0); }\n");

  contourtty::ShaderCompileOptions options;
  options.entry_point = "mainImage";
  options.tools.glslang_validator = fakeGlslang();
  options.tools.spirv_cross = fakeSpirvCross();
  options.work_dir = temp.path();

  const auto spirv = contourtty::compileGlslToSpirv(shader, options);
  expect(std::string(reinterpret_cast<const char*>(spirv.data()), spirv.size()) == "SPV0fake", "fake glslang output captured");

  const std::string msl = contourtty::compileSpirvToMsl(spirv, options);
  expect(msl.find("kernel void main0") != std::string::npos, "fake spirv-cross output captured");

  const auto combined = contourtty::compileGlslToSpirvAndMsl(shader, options);
  expect(combined.spirv == spirv, "combined compile keeps spirv bytes");
  expect(combined.msl == msl, "combined compile keeps msl source");

  const auto seen = temp.path() / "seen-wrapped.glsl";
  setEnvPath("CONTOURTTY_FAKE_GLSLANG_SEEN", seen);
  const auto shadertoy = contourtty::compileShadertoyFragmentToSpirvAndMsl(
    "void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(fragCoord, iTime, 1.0); }\n",
    options);
  unsetEnv("CONTOURTTY_FAKE_GLSLANG_SEEN");
  expect(shadertoy.spirv == spirv, "Shadertoy compile keeps spirv bytes");
  expect(shadertoy.msl == msl, "Shadertoy compile keeps msl source");
  const std::string seen_source = readFile(seen);
  expect(seen_source.find("contourttyFragColor") != std::string::npos, "wrapped Shadertoy source passed to glslang");
  expect(seen_source.find("mainImage(color, contourttyFragCoord);") != std::string::npos, "wrapped source has main bridge");

  contourtty::ShaderCompileOptions missing_tool = options;
  missing_tool.tools.glslang_validator = temp.path() / "missing-glslangValidator";
  expect(throwsShaderError([&] { (void)contourtty::compileGlslToSpirv(shader, missing_tool); }), "missing glslang reports shader error");
  expect(throwsShaderError([&] { (void)contourtty::compileGlslSourceToSpirv("", options); }), "empty glsl source rejected");
  expect(throwsShaderError([&] { (void)contourtty::compileSpirvToMsl({}, options); }), "empty spirv rejected");
  expect(throwsShaderError([&] { (void)contourtty::compileGlslToSpirv(temp.path() / "missing.glsl", options); }), "missing shader source rejected");
}
