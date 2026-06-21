#include "cli.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace {

namespace fs = std::filesystem;

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

void setConfigRoot(const fs::path& root) {
  fs::create_directories(root / "contourtty");
  const std::string value = root.string();
#ifdef _WIN32
  _putenv_s("XDG_CONFIG_HOME", value.c_str());
#else
  setenv("XDG_CONFIG_HOME", value.c_str(), 1);
#endif
}

void writeConfig(const fs::path& root, const std::string& text) {
  setConfigRoot(root);
  std::ofstream output(root / "contourtty" / "config");
  output << text;
}

}  // namespace

int main() {
  const fs::path test_root = fs::temp_directory_path() / "contourtty-cli-tests";
  fs::remove_all(test_root);
  setConfigRoot(test_root / "empty");

  {
    const char* argv[] = {"contourtty", "--dog-sigma", "0"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "dog sigma 0 parses");
    expect(parsed.options.dog_sigma.has_value() && *parsed.options.dog_sigma == 0.0, "dog sigma disables");
    expect(!parsed.options.dog_sigma2.has_value(), "dog sigma2 absent for disable");
  }

  {
    const char* argv[] = {"contourtty", "--dog-sigma", "0.8,1.6", "--dog-threshold", "0.04"};
    const auto parsed = contourtty::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "dog sigma pair parses");
    expect(parsed.options.dog_sigma.has_value() && *parsed.options.dog_sigma == 0.8, "dog sigma1 stored");
    expect(parsed.options.dog_sigma2.has_value() && *parsed.options.dog_sigma2 == 1.6, "dog sigma2 stored");
    expect(parsed.options.dog_threshold.has_value() && *parsed.options.dog_threshold == 0.04, "dog threshold stored");
  }

  {
    const char* argv[] = {"contourtty", "--dog-sigma", "1.0,0.5"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "dog sigma rejects reversed pair");
  }

  {
    const char* argv[] = {"contourtty", "--mode", "structure", "--charset", ".#"};
    const auto parsed = contourtty::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "mode and charset parse");
    expect(parsed.options.mode == "structure", "mode stored");
    expect(parsed.options.charset.has_value() && *parsed.options.charset == ".#", "charset stored");
  }

  {
    const char* argv[] = {"contourtty", "--mode", "blocks"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "blocks mode parses");
    expect(parsed.options.mode == "blocks", "blocks mode stored");
  }

  {
    const char* argv[] = {"contourtty", "--mode", "octant"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "octant mode parses");
    expect(parsed.options.mode == "octant", "octant mode stored");
  }

  {
    const char* argv[] = {"contourtty", "--mode", "sextant"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "sextant mode parses");
    expect(parsed.options.mode == "sextant", "sextant mode stored");
  }

  {
    const char* argv[] = {"contourtty", "--mode", "braille"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "braille mode parses");
    expect(parsed.options.mode == "braille", "braille mode stored");
  }

  {
    const char* argv[] = {"contourtty", "--mode", "auto", "--render-mode", "hybrid"};
    const auto parsed = contourtty::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "auto mode parses");
    expect(parsed.options.mode == "auto", "auto mode stored");
    expect(parsed.options.render_mode == "hybrid", "render mode stored");
  }

  {
    const char* argv[] = {"contourtty", "--pipeline", "structure"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "structure", "pipeline stored");
    expect(parsed.options.mode == "structure", "pipeline maps mode");
  }

  {
    const char* argv[] = {"contourtty", "--pipeline", "blocks"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "blocks pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "blocks", "blocks pipeline stored");
    expect(parsed.options.mode == "blocks", "blocks pipeline maps mode");
  }

  {
    const char* argv[] = {"contourtty", "--pipeline", "octant"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "octant pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "octant", "octant pipeline stored");
    expect(parsed.options.mode == "octant", "octant pipeline maps mode");
  }

  {
    const char* argv[] = {"contourtty", "--pipeline", "sextant"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "sextant pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "sextant", "sextant pipeline stored");
    expect(parsed.options.mode == "sextant", "sextant pipeline maps mode");
  }

  {
    const char* argv[] = {"contourtty", "--pipeline", "braille"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "braille pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "braille", "braille pipeline stored");
    expect(parsed.options.mode == "braille", "braille pipeline maps mode");
  }

  {
    const char* argv[] = {"contourtty", "--pipeline", "auto"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "auto pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "auto", "auto pipeline stored");
    expect(parsed.options.mode == "auto", "auto pipeline maps mode");
  }

  {
    const char* argv[] = {"contourtty", "--pipeline", "invalid"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "pipeline rejects invalid value");
  }

  {
    const char* argv[] = {"contourtty", "--font", "/tmp/font.ttf"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "font parses");
    expect(parsed.options.font_path.has_value() && *parsed.options.font_path == "/tmp/font.ttf", "font stored");
  }

  {
    const char* argv[] = {"contourtty", "--font", ""};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "font rejects empty value");
  }

  {
    const char* argv[] = {"contourtty", "--glyph-features", "hog"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "glyph features parse");
    expect(parsed.options.glyph_features == "hog", "glyph features stored");
  }

  {
    const char* argv[] = {"contourtty", "--glyph-features", "sdf"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "sdf glyph features parse");
    expect(parsed.options.glyph_features == "sdf", "sdf glyph features stored");
  }

  {
    const char* argv[] = {"contourtty", "--ramp-sort"};
    const auto parsed = contourtty::parseArgs(2, const_cast<char**>(argv));
    expect(parsed.error.empty(), "ramp sort parses");
    expect(parsed.options.ramp_sort, "ramp sort stored");
  }

  {
    writeConfig(test_root / "ramp-sort", "ramp-sort=true\n");
    const char* argv[] = {"contourtty", "--no-ramp-sort"};
    const auto parsed = contourtty::parseArgs(2, const_cast<char**>(argv));
    expect(parsed.error.empty(), "no ramp sort parses");
    expect(!parsed.options.ramp_sort, "no ramp sort overrides config");
  }

  {
    const char* argv[] = {"contourtty", "--input", "cam"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "input flag parses");
    expect(parsed.options.input.has_value() && *parsed.options.input == "cam", "input flag stored");
    expect(parsed.options.mirror, "camera mirror defaults on");
  }

  {
    const char* argv[] = {"contourtty", "--input", "cam", "--no-mirror"};
    const auto parsed = contourtty::parseArgs(4, const_cast<char**>(argv));
    expect(parsed.error.empty(), "no mirror parses");
    expect(!parsed.options.mirror, "no mirror stored");
  }

  {
    const char* argv[] = {"contourtty", "--debug-stats", "--no-debug-stats"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "debug stats flags parse");
    expect(!parsed.options.debug_stats, "debug stats disable stored");
  }

  {
    const char* argv[] = {"contourtty", "--graph", "dump"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "graph dump parses");
    expect(parsed.options.graph.has_value() && *parsed.options.graph == "dump", "graph dump stored");
  }

  {
    const char* argv[] = {"contourtty", "--graph", "bad"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "graph rejects invalid value");
  }

  {
    const char* argv[] = {"contourtty", "--caps", "dump"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "caps dump parses");
    expect(parsed.options.caps.has_value() && *parsed.options.caps == "dump", "caps dump stored");
  }

  {
    const char* argv[] = {"contourtty", "--mode", "invalid"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "mode rejects invalid value");
  }

  {
    const char* argv[] = {"contourtty", "--charset", ""};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "charset rejects empty value");
  }

  {
    const char* argv[] = {"contourtty", "--edge-threshold", "0.25", "--contrast", "2"};
    const auto parsed = contourtty::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "edge threshold and contrast parse");
    expect(parsed.options.edge_threshold.has_value() && *parsed.options.edge_threshold == 0.25, "edge threshold stored");
    expect(parsed.options.contrast.has_value() && *parsed.options.contrast == 2.0, "contrast stored");
  }

  {
    const char* argv[] = {"contourtty", "--edge-strength", "1.5"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "edge strength parses");
    expect(parsed.options.edge_strength.has_value() && *parsed.options.edge_strength == 1.5, "edge strength stored");
  }

  {
    const char* argv[] = {"contourtty", "--edge-strength", "-1"};
    const auto parsed = contourtty::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "edge strength rejects negative");
  }

  {
    writeConfig(test_root / "defaults", "pipeline=structure\ncharset=\" .#\"\nwidth=33\nfit=true\nmirror=false\nmono=true\ndebug-stats=true\n");
    const char* argv[] = {"contourtty", "movie.mp4"};
    const auto parsed = contourtty::parseArgs(2, const_cast<char**>(argv));
    expect(parsed.error.empty(), "config defaults parse");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "structure", "config pipeline stored");
    expect(parsed.options.mode == "structure", "config pipeline maps mode");
    expect(parsed.options.charset.has_value() && *parsed.options.charset == " .#", "config charset stored");
    expect(parsed.options.width.has_value() && *parsed.options.width == 33, "config width stored");
    expect(parsed.options.fit, "config fit stored");
    expect(!parsed.options.mirror, "config mirror stored");
    expect(parsed.options.color_mode == "mono", "config mono stored");
    expect(parsed.options.debug_stats, "config debug stats stored");
    expect(parsed.options.input.has_value() && *parsed.options.input == "movie.mp4", "config keeps cli input");
  }

  {
    const char* argv[] = {"contourtty", "--pipeline", "luminance", "--charset", "@%", "--width", "44", "--no-fit", "--mirror", "--no-debug-stats", "--color-mode", "truecolor", "movie.mp4"};
    const auto parsed = contourtty::parseArgs(13, const_cast<char**>(argv));
    expect(parsed.error.empty(), "cli overrides config parse");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "luminance", "cli pipeline overrides config");
    expect(parsed.options.mode == "luminance", "cli pipeline maps mode");
    expect(parsed.options.charset.has_value() && *parsed.options.charset == "@%", "cli charset overrides config");
    expect(parsed.options.width.has_value() && *parsed.options.width == 44, "cli width overrides config");
    expect(!parsed.options.fit, "cli no-fit overrides config");
    expect(parsed.options.mirror, "cli mirror overrides config");
    expect(!parsed.options.debug_stats, "cli debug stats overrides config");
    expect(parsed.options.color_mode == "truecolor", "cli color overrides config mono");
  }

  {
    writeConfig(test_root / "bad", "width=0\n");
    const char* argv[] = {"contourtty", "movie.mp4"};
    const auto parsed = contourtty::parseArgs(2, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "invalid config fails");
  }

  {
    const char* argv[] = {"contourtty", "--help"};
    const auto parsed = contourtty::parseArgs(2, const_cast<char**>(argv));
    expect(parsed.error.empty(), "help bypasses invalid config");
    expect(parsed.action == contourtty::CliAction::Help, "help action bypasses invalid config");
  }

  fs::remove_all(test_root);
}
