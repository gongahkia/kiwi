#include "shader_compiler.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
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
  TempTree() : path_(std::filesystem::temp_directory_path() / ("contourtty-shader-test-" + std::to_string(getpid()))) {
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

std::filesystem::path writeFile(const std::filesystem::path& path, const std::string& contents, bool executable = false) {
  {
    std::ofstream out(path);
    out << contents;
  }
  if (executable) {
    chmod(path.c_str(), 0700);
  }
  return path;
}

std::string readFile(const std::filesystem::path& path) {
  std::ifstream input(path);
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

std::filesystem::path fakeGlslang(const std::filesystem::path& dir) {
  return writeFile(dir / "fake-glslangValidator",
                   "#!/bin/sh\n"
                   "out=''\n"
                   "input=''\n"
                   "stage=''\n"
                   "entry=''\n"
                   "while [ \"$#\" -gt 0 ]; do\n"
                   "  case \"$1\" in\n"
                   "    -o) shift; out=\"$1\" ;;\n"
                   "    -S) shift; stage=\"$1\" ;;\n"
                   "    -e) shift; entry=\"$1\" ;;\n"
                   "    -*) ;;\n"
                   "    *) input=\"$1\" ;;\n"
                   "  esac\n"
                   "  shift\n"
                   "done\n"
                   "[ \"$stage\" = frag ] || exit 42\n"
                   "[ \"$entry\" = mainImage ] || exit 43\n"
                   "[ -n \"$out\" ] || exit 44\n"
                   "[ -n \"$input\" ] || exit 45\n"
                   "[ -n \"$CONTOURTTY_FAKE_GLSLANG_SEEN\" ] && cp \"$input\" \"$CONTOURTTY_FAKE_GLSLANG_SEEN\"\n"
                   "printf 'SPV0fake' > \"$out\"\n",
                   true);
}

std::filesystem::path fakeSpirvCross(const std::filesystem::path& dir) {
  return writeFile(dir / "fake-spirv-cross",
                   "#!/bin/sh\n"
                   "input=\"$1\"\n"
                   "out=''\n"
                   "while [ \"$#\" -gt 0 ]; do\n"
                   "  case \"$1\" in\n"
                   "    --output) shift; out=\"$1\" ;;\n"
                   "  esac\n"
                   "  shift\n"
                   "done\n"
                   "[ -s \"$input\" ] || exit 45\n"
                   "[ -n \"$out\" ] || exit 46\n"
                   "printf '// msl from fake\\nkernel void main0() {}\\n' > \"$out\"\n",
                   true);
}

bool throwsShaderError(const std::function<void()>& body) {
  try {
    body();
  } catch (const contourtty::ShaderCompileError&) {
    return true;
  }
  return false;
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
  options.tools.glslang_validator = fakeGlslang(temp.path());
  options.tools.spirv_cross = fakeSpirvCross(temp.path());
  options.work_dir = temp.path();

  const auto spirv = contourtty::compileGlslToSpirv(shader, options);
  expect(std::string(reinterpret_cast<const char*>(spirv.data()), spirv.size()) == "SPV0fake", "fake glslang output captured");

  const std::string msl = contourtty::compileSpirvToMsl(spirv, options);
  expect(msl.find("kernel void main0") != std::string::npos, "fake spirv-cross output captured");

  const auto combined = contourtty::compileGlslToSpirvAndMsl(shader, options);
  expect(combined.spirv == spirv, "combined compile keeps spirv bytes");
  expect(combined.msl == msl, "combined compile keeps msl source");

  const auto seen = temp.path() / "seen-wrapped.glsl";
  setenv("CONTOURTTY_FAKE_GLSLANG_SEEN", seen.c_str(), 1);
  const auto shadertoy = contourtty::compileShadertoyFragmentToSpirvAndMsl(
    "void mainImage(out vec4 fragColor, in vec2 fragCoord) { fragColor = vec4(fragCoord, iTime, 1.0); }\n",
    options);
  unsetenv("CONTOURTTY_FAKE_GLSLANG_SEEN");
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
