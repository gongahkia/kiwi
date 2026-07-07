#include "shader_source.hpp"

#include <cstdlib>
#include <filesystem>
#include <functional>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <unistd.h>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

class TempTree {
 public:
  TempTree() : path_(std::filesystem::temp_directory_path() / ("contourtty-shader-source-test-" + std::to_string(getpid()))) {
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
  std::ofstream out(path);
  out << contents;
  return path;
}

bool throwsSourceError(const std::function<void()>& body) {
  try {
    body();
  } catch (const contourtty::ShaderSourceError&) {
    return true;
  }
  return false;
}

}  // namespace

int main() {
  expect(contourtty::isShaderSourcePath("effect.glsl"), "glsl shader path");
  expect(contourtty::isShaderSourcePath("effect.FRAG"), "uppercase frag shader path");
  expect(contourtty::isShaderSourcePath("effect.comp"), "compute shader path");
  expect(!contourtty::isShaderSourcePath("movie.mp4"), "movie is not shader path");

  const std::string shadertoy =
    "void mainImage(out vec4 fragColor, in vec2 fragCoord) {\n"
    "  vec2 uv = fragCoord / iResolution.xy;\n"
    "  fragColor = texture(iChannel0, uv) + vec4(iTimeDelta + float(iFrame));\n"
    "}\n";
  expect(contourtty::isShadertoySource(shadertoy), "mainImage source detected");
  const std::string wrapped = contourtty::wrapShadertoyFragmentShader(shadertoy);
  expect(wrapped.starts_with("#version 450\n"), "default version emitted");
  expect(wrapped.find("layout(location = 0) out vec4 contourttyFragColor;") != std::string::npos, "fragment output emitted");
  expect(wrapped.find("#define iResolution contourttyUniforms.iResolution") != std::string::npos, "iResolution macro emitted");
  expect(wrapped.find("uniform sampler2D iChannel3;") != std::string::npos, "channel sampler emitted");
  expect(wrapped.find("mainImage(color, contourttyFragCoord);") != std::string::npos, "main delegates to mainImage");

  const std::string versioned = "#version 460\nvoid mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(fragCoord, 0.0, 1.0); }\n";
  const std::string versioned_wrapped = contourtty::wrapShadertoyFragmentShader(versioned);
  expect(versioned_wrapped.starts_with("#version 460\n"), "source version preserved");
  expect(versioned_wrapped.find("#version 450") == std::string::npos, "default version not duplicated");
  expect(throwsSourceError([&] { (void)contourtty::wrapShadertoyFragmentShader("void main() {}\n"); }), "missing mainImage rejected");

  TempTree temp;
  const auto path = writeFile(temp.path() / "shader.glsl", shadertoy);
  expect(contourtty::loadShaderSource(path) == shadertoy, "shader source loads");
  expect(throwsSourceError([&] { (void)contourtty::loadShaderSource(temp.path() / "missing.glsl"); }), "missing shader source reports error");
}
