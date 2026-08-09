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
  fs::create_directories(root / "strok");
  const std::string value = root.string();
#ifdef _WIN32
  _putenv_s("XDG_CONFIG_HOME", value.c_str());
#else
  setenv("XDG_CONFIG_HOME", value.c_str(), 1);
#endif
}

void writeConfig(const fs::path& root, const std::string& text) {
  setConfigRoot(root);
  std::ofstream output(root / "strok" / "config");
  output << text;
}

}  // namespace

int main() {
  const fs::path test_root = fs::temp_directory_path() / "strok-cli-tests";
  fs::remove_all(test_root);
  setConfigRoot(test_root / "empty");

  {
    const char* argv[] = {"strok", "--dog-sigma", "0"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "dog sigma 0 parses");
    expect(parsed.options.dog_sigma.has_value() && *parsed.options.dog_sigma == 0.0, "dog sigma disables");
    expect(!parsed.options.dog_sigma2.has_value(), "dog sigma2 absent for disable");
  }

  {
    const char* argv[] = {
      "strok",
      "--input-open-timeout", "1200",
      "--read-timeout", "2400",
      "--rtsp-transport", "tcp",
      "--no-reconnect",
      "--reconnect-backoff", "750",
    };
    const auto parsed = strok::parseArgs(10, const_cast<char**>(argv));
    expect(parsed.error.empty(), "live input options parse");
    expect(parsed.options.input_open_timeout_ms == 1200, "open timeout stored");
    expect(parsed.options.read_timeout_ms == 2400, "read timeout stored");
    expect(parsed.options.rtsp_transport == "tcp", "rtsp transport stored");
    expect(!parsed.options.reconnect, "reconnect disabled");
    expect(parsed.options.reconnect_backoff_ms == 750, "reconnect backoff stored");
  }

  {
    const char* argv[] = {"strok", "--rtsp-transport", "sctp"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "rtsp transport rejects invalid value");
  }

  {
    const char* argv[] = {"strok", "--read-timeout", "-1"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "read timeout rejects negative value");
  }

  {
    const char* argv[] = {"strok", "--dog-sigma", "0.8,1.6", "--dog-threshold", "0.04"};
    const auto parsed = strok::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "dog sigma pair parses");
    expect(parsed.options.dog_sigma.has_value() && *parsed.options.dog_sigma == 0.8, "dog sigma1 stored");
    expect(parsed.options.dog_sigma2.has_value() && *parsed.options.dog_sigma2 == 1.6, "dog sigma2 stored");
    expect(parsed.options.dog_threshold.has_value() && *parsed.options.dog_threshold == 0.04, "dog threshold stored");
  }

  {
    const char* argv[] = {"strok", "--dog-sigma", "1.0,0.5"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "dog sigma rejects reversed pair");
  }

  {
    const char* argv[] = {"strok", "--mode", "structure", "--charset", ".#"};
    const auto parsed = strok::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "mode and charset parse");
    expect(parsed.options.mode == "structure", "mode stored");
    expect(parsed.options.charset.has_value() && *parsed.options.charset == ".#", "charset stored");
  }

  {
    const char* argv[] = {"strok", "--mode", "blocks"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "blocks mode parses");
    expect(parsed.options.mode == "blocks", "blocks mode stored");
  }

  {
    const char* argv[] = {"strok", "--mode", "octant"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "octant mode parses");
    expect(parsed.options.mode == "octant", "octant mode stored");
  }

  {
    const char* argv[] = {"strok", "--mode", "sextant"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "sextant mode parses");
    expect(parsed.options.mode == "sextant", "sextant mode stored");
  }

  {
    const char* argv[] = {"strok", "--mode", "braille"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "braille mode parses");
    expect(parsed.options.mode == "braille", "braille mode stored");
  }

  {
    const char* argv[] = {"strok", "--mode", "auto", "--render-mode", "hybrid"};
    const auto parsed = strok::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "auto mode parses");
    expect(parsed.options.mode == "auto", "auto mode stored");
    expect(parsed.options.render_mode == "hybrid", "render mode stored");
  }

  {
    const char* argv[] = {"strok", "--pipeline", "structure"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "structure", "pipeline stored");
    expect(parsed.options.mode == "structure", "pipeline maps mode");
  }

  {
    const char* argv[] = {"strok", "--pipeline", "blocks"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "blocks pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "blocks", "blocks pipeline stored");
    expect(parsed.options.mode == "blocks", "blocks pipeline maps mode");
  }

  {
    const char* argv[] = {"strok", "--pipeline", "octant"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "octant pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "octant", "octant pipeline stored");
    expect(parsed.options.mode == "octant", "octant pipeline maps mode");
  }

  {
    const char* argv[] = {"strok", "--pipeline", "sextant"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "sextant pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "sextant", "sextant pipeline stored");
    expect(parsed.options.mode == "sextant", "sextant pipeline maps mode");
  }

  {
    const char* argv[] = {"strok", "--pipeline", "braille"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "braille pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "braille", "braille pipeline stored");
    expect(parsed.options.mode == "braille", "braille pipeline maps mode");
  }

  {
    const char* argv[] = {"strok", "--pipeline", "auto"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "auto pipeline parses");
    expect(parsed.options.pipeline.has_value() && *parsed.options.pipeline == "auto", "auto pipeline stored");
    expect(parsed.options.mode == "auto", "auto pipeline maps mode");
  }

  {
    const char* argv[] = {"strok", "--pipeline", "invalid"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "pipeline rejects invalid value");
  }

  {
    const char* argv[] = {"strok", "--font", "/tmp/font.ttf"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "font parses");
    expect(parsed.options.font_path.has_value() && *parsed.options.font_path == "/tmp/font.ttf", "font stored");
  }

  {
    const char* argv[] = {"strok", "--font", ""};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "font rejects empty value");
  }

  {
    const char* argv[] = {"strok", "--glyph-features", "hog"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "glyph features parse");
    expect(parsed.options.glyph_features == "hog", "glyph features stored");
  }

  {
    const char* argv[] = {"strok", "--glyph-features", "sdf"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "sdf glyph features parse");
    expect(parsed.options.glyph_features == "sdf", "sdf glyph features stored");
  }

  {
    const char* argv[] = {"strok", "--structure-overlay", "on"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "structure overlay parses");
    expect(parsed.options.structure_overlay == "on", "structure overlay stored");
  }

  {
    const char* argv[] = {"strok", "--structure-overlay", "bad"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "structure overlay rejects invalid value");
  }

  {
    const char* argv[] = {"strok", "--ramp-sort"};
    const auto parsed = strok::parseArgs(2, const_cast<char**>(argv));
    expect(parsed.error.empty(), "ramp sort parses");
    expect(parsed.options.ramp_sort, "ramp sort stored");
  }

  {
    writeConfig(test_root / "ramp-sort", "ramp-sort=true\n");
    const char* argv[] = {"strok", "--no-ramp-sort"};
    const auto parsed = strok::parseArgs(2, const_cast<char**>(argv));
    expect(parsed.error.empty(), "no ramp sort parses");
    expect(!parsed.options.ramp_sort, "no ramp sort overrides config");
  }

  {
    const char* argv[] = {"strok", "--input", "cam"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "input flag parses");
    expect(parsed.options.input.has_value() && *parsed.options.input == "cam", "input flag stored");
    expect(parsed.options.mirror, "camera mirror defaults on");
  }

  {
    const char* argv[] = {"strok", "--input", "cam", "--no-mirror"};
    const auto parsed = strok::parseArgs(4, const_cast<char**>(argv));
    expect(parsed.error.empty(), "no mirror parses");
    expect(!parsed.options.mirror, "no mirror stored");
  }

  {
    const char* argv[] = {"strok", "--debug-stats", "--no-debug-stats"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "debug stats flags parse");
    expect(!parsed.options.debug_stats, "debug stats disable stored");
  }

  {
    const char* argv[] = {"strok", "--line-ligatures", "--no-line-ligatures"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "line ligature flags parse");
    expect(!parsed.options.line_ligatures, "line ligature disable stored");
  }

  {
    const char* argv[] = {"strok", "--input-keys", "ism246q"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "input keys parse");
    expect(parsed.options.input_keys.has_value() && *parsed.options.input_keys == "ism246q", "input keys stored");
  }

  {
    const char* argv[] = {"strok", "--temporal-supersample", "2"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "temporal supersample parses");
    expect(parsed.options.temporal_supersample == 2, "temporal supersample stored");
  }

  {
    const char* argv[] = {"strok", "--temporal-supersample", "0"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "temporal supersample rejects zero");
  }

  {
    const char* argv[] = {"strok", "--graph", "dump"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "graph dump parses");
    expect(parsed.options.graph.has_value() && *parsed.options.graph == "dump", "graph dump stored");
  }

  {
    const char* argv[] = {"strok", "--graph", "share/strok/graphs/structure.yaml"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "graph file parses");
    expect(parsed.options.graph.has_value() && *parsed.options.graph == "share/strok/graphs/structure.yaml", "graph file stored");
  }

  {
    const char* argv[] = {"strok", "--graph", ""};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "graph rejects empty value");
  }

  {
    const char* argv[] = {"strok", "--split", "luminance:structure"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "split parses");
    expect(parsed.options.split.has_value() && *parsed.options.split == "luminance:structure", "split stored");
  }

  {
    const char* argv[] = {"strok", "--split", "luminance:bad"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "split rejects invalid value");
  }

  {
    const char* argv[] = {"strok", "--grid", "4x3"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "grid parses");
    expect(parsed.options.grid.has_value() && *parsed.options.grid == "4x3", "grid stored");
  }

  {
    const char* argv[] = {"strok", "--grid", "4"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "grid rejects invalid value");
  }

  {
    const char* argv[] = {"strok", "--input", "stdin", "--plot", "waveform", "--plot-window", "512", "--plot-rate", "20"};
    const auto parsed = strok::parseArgs(9, const_cast<char**>(argv));
    expect(parsed.error.empty(), "stdin plot flags parse");
    expect(parsed.options.input.has_value() && *parsed.options.input == "stdin", "stdin input stored");
    expect(parsed.options.plot.has_value() && *parsed.options.plot == "waveform", "plot stored");
    expect(parsed.options.plot_window == 512, "plot window stored");
    expect(parsed.options.plot_rate_hz == 20.0, "plot rate stored");
  }

  {
    const char* argv[] = {"strok", "--plot", "bad"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "plot rejects invalid value");
  }

  {
    const char* argv[] = {"strok", "--overlay", "scene.obj"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "overlay parses");
    expect(parsed.options.overlay.has_value() && *parsed.options.overlay == "scene.obj", "overlay stored");
  }

  {
    const char* argv[] = {"strok", "--overlay-alpha", "0.25", "--overlay-depth-threshold", "4.5"};
    const auto parsed = strok::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "overlay controls parse");
    expect(parsed.options.overlay_alpha == 0.25, "overlay alpha stored");
    expect(parsed.options.overlay_depth_threshold == 4.5, "overlay depth threshold stored");
  }

  {
    const char* argv[] = {"strok", "--overlay-alpha", "1.5"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "overlay alpha rejects above one");
  }

  {
    const char* argv[] = {"strok", "--overlay", ""};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "overlay rejects empty");
  }

  {
    const char* argv[] = {"strok", "--captions", "out.srt"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "captions parses");
    expect(parsed.options.captions_file.has_value() && *parsed.options.captions_file == "out.srt", "captions stored");
  }

  {
    const char* argv[] = {"strok", "--captions", ""};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "captions rejects empty");
  }

  {
    const char* argv[] = {"strok", "--still", "hero.png", "--still-at", "01:02:03.004"};
    const auto parsed = strok::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "still snapshot parses");
    expect(parsed.options.still_file.has_value() && *parsed.options.still_file == "hero.png", "still path stored");
    expect(parsed.options.still_at_us.has_value() && *parsed.options.still_at_us == 3723004000, "still timestamp stored");
  }

  {
    const char* argv[] = {"strok", "--still", ""};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "still rejects empty");
  }

  {
    const char* argv[] = {"strok", "--still-at", "2"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "still timestamp rejects malformed value");
  }

  {
    const char* argv[] = {"strok", "--scene-camera", "orbit"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "scene camera parses");
    expect(parsed.options.scene_camera == "orbit", "scene camera stored");
  }

  {
    const char* argv[] = {"strok", "--scene-camera", "bad"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "scene camera rejects invalid value");
  }

  {
    const char* argv[] = {"strok", "--caps", "dump"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "caps dump parses");
    expect(parsed.options.caps.has_value() && *parsed.options.caps == "dump", "caps dump stored");
  }

  {
    const char* argv[] = {"strok", "--mode", "invalid"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "mode rejects invalid value");
  }

  {
    const char* argv[] = {"strok", "--style", "painterly"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "painterly style parses");
    expect(parsed.options.style == "painterly", "painterly style stored");
  }

  {
    const char* argv[] = {"strok", "--style", "hatch"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "hatch style parses");
    expect(parsed.options.style == "hatch", "hatch style stored");
  }

  {
    const char* argv[] = {"strok", "--style", "stipple"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "stipple style parses");
    expect(parsed.options.style == "stipple", "stipple style stored");
  }

  {
    const char* argv[] = {"strok", "--style", "flow"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "flow style parses");
    expect(parsed.options.style == "flow", "flow style stored");
  }

  {
    const char* argv[] = {"strok", "--style", "cell-shade"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "cell shade style parses");
    expect(parsed.options.style == "cell-shade", "cell shade style stored");
  }

  {
    const char* argv[] = {"strok", "--style", "invalid"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "style rejects invalid value");
  }

  {
    const char* argv[] = {"strok", "--style", "hatch", "--style", "flow"};
    const auto parsed = strok::parseArgs(5, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "style rejects duplicate value");
  }

  {
    const char* argv[] = {"strok", "--charset", ""};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "charset rejects empty value");
  }

  {
    const char* argv[] = {"strok", "--edge-threshold", "0.25", "--contrast", "2"};
    const auto parsed = strok::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "edge threshold and contrast parse");
    expect(parsed.options.edge_threshold.has_value() && *parsed.options.edge_threshold == 0.25, "edge threshold stored");
    expect(parsed.options.contrast.has_value() && *parsed.options.contrast == 2.0, "contrast stored");
  }

  {
    const char* argv[] = {"strok", "--edge-strength", "1.5"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "edge strength parses");
    expect(parsed.options.edge_strength.has_value() && *parsed.options.edge_strength == 1.5, "edge strength stored");
  }

  {
    const char* argv[] = {"strok", "--edge-strength", "-1"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "edge strength rejects negative");
  }

  {
    const char* argv[] = {"strok", "--etf-iters", "3"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "etf iters parse");
    expect(parsed.options.etf_iters.has_value() && *parsed.options.etf_iters == 3, "etf iters stored");
  }

  {
    const char* argv[] = {"strok", "--etf-iters", "17"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "etf iters rejects excessive value");
  }

  {
    const char* argv[] = {"strok", "--lic-length", "12"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "LIC length parses");
    expect(parsed.options.lic_length.has_value() && *parsed.options.lic_length == 12, "LIC length stored");
  }

  {
    const char* argv[] = {"strok", "--lic-length", "0"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "LIC length rejects zero");
  }

  {
    const char* argv[] = {"strok", "--posterize", "4"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "posterize parses");
    expect(parsed.options.posterize.has_value() && *parsed.options.posterize == 4, "posterize stored");
  }

  {
    const char* argv[] = {"strok", "--posterize", "1"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "posterize rejects one level");
  }

  {
    const char* argv[] = {"strok", "--diff-oklab-eps", "0.01"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "diff OKLab epsilon parses");
    expect(parsed.options.diff_oklab_eps.has_value() && *parsed.options.diff_oklab_eps == 0.01, "diff OKLab epsilon stored");
  }

  {
    const char* argv[] = {"strok", "--bandwidth-cap", "12.5"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "bandwidth cap parses");
    expect(parsed.options.bandwidth_cap_mb_s == 12.5, "bandwidth cap stored");
  }

  {
    const char* argv[] = {"strok", "--bandwidth-cap", "0"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "bandwidth cap rejects zero");
  }

  {
    const char* argv[] = {"strok", "--glyph-stickiness", "0.08"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "glyph stickiness parses");
    expect(parsed.options.glyph_stickiness.has_value() && *parsed.options.glyph_stickiness == 0.08, "glyph stickiness stored");
  }

  {
    const char* argv[] = {"strok", "--orient-stickiness", "0.12"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "orientation stickiness parses");
    expect(parsed.options.orient_stickiness.has_value() && *parsed.options.orient_stickiness == 0.12, "orientation stickiness stored");
  }

  {
    const char* argv[] = {"strok", "--orient-stickiness", "4"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "orientation stickiness rejects above pi");
  }

  {
    const char* argv[] = {"strok", "--profile", "live"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(parsed.error.empty(), "live profile parses");
    expect(parsed.options.profile.has_value() && *parsed.options.profile == "live", "live profile stored");
    expect(parsed.options.mode == "luminance", "live profile uses luminance");
    expect(parsed.options.max_fps.has_value() && *parsed.options.max_fps == 30.0, "live profile limits presentation fps");
    expect(parsed.options.fit, "live profile fits output");
  }

  {
    const char* argv[] = {"strok", "--profile", "structure", "--width", "96"};
    const auto parsed = strok::parseArgs(5, const_cast<char**>(argv));
    expect(parsed.error.empty(), "structure profile parses");
    expect(parsed.options.mode == "structure", "structure profile sets mode");
    expect(parsed.options.glyph_features == "hog", "structure profile selects HoG");
    expect(parsed.options.width.has_value() && *parsed.options.width == 96, "cli flag overrides profile");
  }

  {
    const char* argv[] = {"strok", "--profile", "invalid"};
    const auto parsed = strok::parseArgs(3, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "invalid profile is rejected");
  }

  {
    const char* argv[] = {"strok", "--profile", "live", "--profile", "structure"};
    const auto parsed = strok::parseArgs(5, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "duplicate profile is rejected");
  }

  {
    const char* argv[] = {"strok", "--doctor", "--profile", "low-bandwidth"};
    const auto parsed = strok::parseArgs(4, const_cast<char**>(argv));
    expect(parsed.error.empty(), "doctor profile parses");
    expect(parsed.action == strok::CliAction::Doctor, "doctor action stored");
    expect(parsed.options.profile.has_value() && *parsed.options.profile == "low-bandwidth", "doctor keeps selected profile");
    expect(parsed.options.max_fps.has_value() && *parsed.options.max_fps == 12.0, "doctor sees effective profile settings");
  }

  {
    writeConfig(test_root / "defaults", "pipeline=structure\ncharset=\" .#\"\nwidth=33\nfit=true\nmirror=false\nmono=true\ndebug-stats=true\n");
    const char* argv[] = {"strok", "movie.mp4"};
    const auto parsed = strok::parseArgs(2, const_cast<char**>(argv));
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
    expect(parsed.config_path.has_value(), "config source recorded");
  }

  {
    writeConfig(test_root / "profile", "profile=low-bandwidth\nwidth=44\nmax-fps=9\n");
    const char* argv[] = {"strok", "movie.mp4"};
    const auto parsed = strok::parseArgs(2, const_cast<char**>(argv));
    expect(parsed.error.empty(), "config profile parses");
    expect(parsed.options.profile.has_value() && *parsed.options.profile == "low-bandwidth", "config profile stored");
    expect(parsed.options.mode == "luminance", "config profile sets mode");
    expect(parsed.options.color_mode == "16", "config profile sets color mode");
    expect(parsed.options.max_fps.has_value() && *parsed.options.max_fps == 9.0, "config entry overrides config profile");
    expect(parsed.options.width.has_value() && *parsed.options.width == 44, "config entry keeps explicit width");
  }

  {
    const char* argv[] = {"strok", "--profile", "export", "movie.mp4"};
    const auto parsed = strok::parseArgs(4, const_cast<char**>(argv));
    expect(parsed.error.empty(), "cli profile overrides config profile");
    expect(parsed.options.profile.has_value() && *parsed.options.profile == "export", "cli profile replaces config profile");
    expect(parsed.options.mode == "structure", "export profile sets structure mode");
    expect(parsed.options.color_mode == "truecolor", "export profile replaces config color mode");
    expect(!parsed.options.fit, "export profile disables terminal fit");
  }

  {
    const char* argv[] = {"strok", "--profile", "export", "--color-mode", "mono", "movie.mp4"};
    const auto parsed = strok::parseArgs(6, const_cast<char**>(argv));
    expect(parsed.error.empty(), "cli profile with override parses");
    expect(parsed.options.color_mode == "mono", "cli flags override cli profile");
  }

  {
    setConfigRoot(test_root / "defaults");
    const char* argv[] = {"strok", "--pipeline", "luminance", "--charset", "@%", "--width", "44", "--no-fit", "--mirror", "--no-debug-stats", "--color-mode", "truecolor", "movie.mp4"};
    const auto parsed = strok::parseArgs(13, const_cast<char**>(argv));
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
    const char* argv[] = {"strok", "movie.mp4"};
    const auto parsed = strok::parseArgs(2, const_cast<char**>(argv));
    expect(!parsed.error.empty(), "invalid config fails");
  }

  {
    const char* argv[] = {"strok", "--help"};
    const auto parsed = strok::parseArgs(2, const_cast<char**>(argv));
    expect(parsed.error.empty(), "help bypasses invalid config");
    expect(parsed.action == strok::CliAction::Help, "help action bypasses invalid config");
  }

  fs::remove_all(test_root);
}
