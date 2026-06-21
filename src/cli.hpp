#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace contourtty {

enum class CliAction {
  Run,
  Help,
  Version,
};

struct CliOptions {
  std::optional<std::string> input;
  std::optional<int> width;
  std::optional<int> height;
  double cell_aspect = 0.5;
  std::optional<double> fps;
  std::optional<double> max_fps;
  std::string mode = "luminance";
  std::optional<std::string> pipeline;
  std::optional<std::string> font_path;
  std::string color_mode = "auto";
  std::optional<std::string> charset;
  std::optional<double> edge_threshold;
  std::optional<double> edge_strength;
  std::optional<double> dog_sigma;
  std::optional<double> dog_sigma2;
  std::optional<double> dog_threshold;
  std::optional<double> contrast;
  std::string dither = "none";
  bool fit = false;
  bool loop = false;
  bool mirror = true;
  bool gpu = false;
  bool debug_stats = false;
  std::optional<std::string> log_file;
  std::optional<std::string> export_file;
  std::optional<std::string> graph;
  std::optional<int> dump_frame;
  std::optional<std::string> dump_png;
};

struct CliParseResult {
  CliAction action = CliAction::Run;
  CliOptions options;
  std::string error;
};

CliParseResult parseArgs(int argc, char** argv);
std::string helpText(std::string_view program_name);

}  // namespace contourtty
