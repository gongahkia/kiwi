#include "shader_source.hpp"

#include <cstdlib>
#include <filesystem>
#include <functional>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
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
  TempTree() : path_(std::filesystem::temp_directory_path() / ("strok-shader-source-test-" + std::to_string(getpid()))) {
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
  } catch (const strok::ShaderSourceError&) {
    return true;
  }
  return false;
}

std::filesystem::path sourceRoot() {
#ifdef STROK_SOURCE_DIR
  return STROK_SOURCE_DIR;
#else
  return std::filesystem::current_path();
#endif
}

}  // namespace

int main() {
  expect(strok::isShaderSourcePath("effect.glsl"), "glsl shader path");
  expect(strok::isShaderSourcePath("effect.FRAG"), "uppercase frag shader path");
  expect(strok::isShaderSourcePath("effect.comp"), "compute shader path");
  expect(!strok::isShaderSourcePath("movie.mp4"), "movie is not shader path");
  const auto bundled_plasma = strok::resolveBundledShader("strok:shader:plasma");
  expect(bundled_plasma.has_value() && bundled_plasma->filename() == "plasma.glsl", "bundled shader alias resolves");
  expect(!strok::resolveBundledShader("movie.mp4").has_value(), "non shader alias ignored");
  expect(throwsSourceError([&] { (void)strok::resolveBundledShader("strok:shader:missing"); }), "missing bundled shader rejected");

  const std::string shadertoy =
    "void mainImage(out vec4 fragColor, in vec2 fragCoord) {\n"
    "  vec2 uv = fragCoord / iResolution.xy;\n"
    "  fragColor = texture(iChannel0, uv) + vec4(iTimeDelta + float(iFrame));\n"
    "}\n";
  expect(strok::isShadertoySource(shadertoy), "mainImage source detected");
  const std::string wrapped = strok::wrapShadertoyFragmentShader(shadertoy);
  expect(wrapped.starts_with("#version 450\n"), "default version emitted");
  expect(wrapped.find("layout(location = 0) out vec4 strokFragColor;") != std::string::npos, "fragment output emitted");
  expect(wrapped.find("#define iResolution strokUniforms.iResolution") != std::string::npos, "iResolution macro emitted");
  expect(wrapped.find("uniform sampler2D iChannel3;") != std::string::npos, "channel sampler emitted");
  expect(wrapped.find("mainImage(color, strokFragCoord);") != std::string::npos, "main delegates to mainImage");

  const std::string versioned = "#version 460\nvoid mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(fragCoord, 0.0, 1.0); }\n";
  const std::string versioned_wrapped = strok::wrapShadertoyFragmentShader(versioned);
  expect(versioned_wrapped.starts_with("#version 460\n"), "source version preserved");
  expect(versioned_wrapped.find("#version 450") == std::string::npos, "default version not duplicated");
  expect(throwsSourceError([&] { (void)strok::wrapShadertoyFragmentShader("void main() {}\n"); }), "missing mainImage rejected");

  TempTree temp;
  const auto path = writeFile(temp.path() / "shader.glsl", shadertoy);
  expect(strok::loadShaderSource(path) == shadertoy, "shader source loads");
  expect(throwsSourceError([&] { (void)strok::loadShaderSource(temp.path() / "missing.glsl"); }), "missing shader source reports error");

  const auto shader_dir = sourceRoot() / "share" / "strok" / "shaders";
  const std::vector<std::string> bundled = {"noise.glsl", "plasma.glsl", "feedback.glsl", "sdf_room.glsl"};
  for (const std::string& name : bundled) {
    const std::string source = strok::loadShaderSource(shader_dir / name);
    expect(strok::isShadertoySource(source), "bundled shader defines mainImage");
    const std::string wrapped_source = strok::wrapShadertoyFragmentShader(source);
    expect(wrapped_source.find("strokFragColor") != std::string::npos, "bundled shader wraps as fragment output");
  }
}
