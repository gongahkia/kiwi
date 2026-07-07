#include "shader_source.hpp"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>
#include <string>
#include <utility>

namespace contourtty {
namespace {

std::string lowerExtension(std::filesystem::path path) {
  std::string ext = path.extension().string();
  std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return ext;
}

std::string_view trimLeft(std::string_view value) {
  while (!value.empty()) {
    const unsigned char ch = static_cast<unsigned char>(value.front());
    if (!std::isspace(ch)) {
      break;
    }
    value.remove_prefix(1);
  }
  return value;
}

std::pair<std::string_view, std::string_view> splitVersionLine(std::string_view source) {
  const std::string_view trimmed = trimLeft(source);
  if (!trimmed.starts_with("#version")) {
    return {"#version 450\n", source};
  }
  const std::size_t line_end = trimmed.find('\n');
  if (line_end == std::string_view::npos) {
    return {trimmed, {}};
  }
  return {trimmed.substr(0, line_end + 1), trimmed.substr(line_end + 1)};
}

}  // namespace

bool isShaderSourcePath(const std::filesystem::path& path) {
  const std::string ext = lowerExtension(path);
  return ext == ".glsl" || ext == ".frag" || ext == ".vert" || ext == ".comp";
}

std::optional<std::filesystem::path> resolveBundledShader(std::string_view input) {
  constexpr std::string_view prefix = "contourtty:shader:";
  if (!input.starts_with(prefix)) {
    return std::nullopt;
  }
  const std::string name(input.substr(prefix.size()));
  if (name.empty() || name.find('/') != std::string::npos || name.find('\\') != std::string::npos) {
    throw ShaderSourceError("invalid bundled shader name");
  }
  std::filesystem::path path = std::filesystem::path(CONTOURTTY_SOURCE_DIR) / "share" / "contourtty" / "shaders" / (name + ".glsl");
  if (!std::filesystem::exists(path)) {
    throw ShaderSourceError("unknown bundled shader: " + name);
  }
  return path;
}

bool isShadertoySource(std::string_view source) noexcept {
  return source.find("mainImage") != std::string_view::npos;
}

std::string loadShaderSource(const std::filesystem::path& path) {
  std::ifstream input(path);
  if (!input) {
    throw ShaderSourceError("failed to read shader source: " + path.string());
  }
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

std::string wrapShadertoyFragmentShader(std::string_view source) {
  if (!isShadertoySource(source)) {
    throw ShaderSourceError("Shadertoy fragment shader must define mainImage");
  }

  const auto [version, body] = splitVersionLine(source);
  std::ostringstream out;
  out << version;
  if (!version.ends_with('\n')) {
    out << '\n';
  }
  out << R"GLSL(
layout(location = 0) in vec2 contourttyFragCoord;
layout(location = 0) out vec4 contourttyFragColor;

layout(set = 0, binding = 0) uniform ContourttyShaderUniforms {
  vec3 iResolution;
  float iTime;
  float iTimeDelta;
  int iFrame;
  vec4 iMouse;
  vec4 iDate;
  float iSampleRate;
  vec3 iChannelResolution[4];
  float iChannelTime[4];
} contourttyUniforms;

#define iResolution contourttyUniforms.iResolution
#define iTime contourttyUniforms.iTime
#define iTimeDelta contourttyUniforms.iTimeDelta
#define iFrame contourttyUniforms.iFrame
#define iMouse contourttyUniforms.iMouse
#define iDate contourttyUniforms.iDate
#define iSampleRate contourttyUniforms.iSampleRate
#define iChannelResolution contourttyUniforms.iChannelResolution
#define iChannelTime contourttyUniforms.iChannelTime

layout(set = 0, binding = 1) uniform sampler2D iChannel0;
layout(set = 0, binding = 2) uniform sampler2D iChannel1;
layout(set = 0, binding = 3) uniform sampler2D iChannel2;
layout(set = 0, binding = 4) uniform sampler2D iChannel3;

)GLSL";
  out << body;
  if (!body.empty() && body.back() != '\n') {
    out << '\n';
  }
  out << R"GLSL(
void main() {
  vec4 color = vec4(0.0);
  mainImage(color, contourttyFragCoord);
  contourttyFragColor = color;
}
)GLSL";
  return out.str();
}

}  // namespace contourtty
