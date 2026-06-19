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
  std::string color_mode = "auto";
  std::optional<std::string> charset;
  std::optional<double> edge_threshold;
  std::optional<double> dog_sigma;
  std::optional<double> contrast;
  std::string dither = "none";
  bool fit = false;
  bool loop = false;
  bool gpu = false;
  std::optional<std::string> log_file;
  std::optional<std::string> export_file;
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
