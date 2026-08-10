#include "cli.hpp"

#include "cli_spec.hpp"
#include "glyph_ramp.hpp"
#include "image_grid.hpp"
#include "scene_source.hpp"
#include "split.hpp"
#include "stdin_data.hpp"

#include <charconv>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace strok {
namespace {

bool isOneOf(std::string_view value, std::initializer_list<std::string_view> allowed) {
  for (const auto allowed_value : allowed) {
    if (value == allowed_value) {
      return true;
    }
  }
  return false;
}

void applyPipeline(std::string_view value, CliOptions* options);

bool isProfileName(std::string_view value) {
  return isOneOf(value, {"live", "structure", "low-bandwidth", "export"});
}

bool isFfmpegLogLevel(std::string_view value) {
  return isOneOf(value, {"off", "error", "warning", "info", "debug", "trace"});
}

void applyProfile(std::string_view value, CliOptions* options) {
  if (value == "live") {
    applyPipeline("luminance", options);
    options->style = "none";
    options->render_mode = "text";
    options->structure_overlay = "auto";
    options->glyph_features = "overlap";
    options->max_fps = 30.0;
    options->fps.reset();
    options->fit = true;
    options->color_mode = "auto";
    options->dither = "none";
    options->diff_oklab_eps = 0.01;
    options->line_ligatures = false;
    options->debug_stats = false;
    options->reconnect = true;
    return;
  }
  if (value == "structure") {
    applyPipeline("structure", options);
    options->style = "none";
    options->render_mode = "text";
    options->glyph_features = "hog";
    options->structure_overlay = "auto";
    options->max_fps.reset();
    options->fps.reset();
    options->fit = true;
    options->color_mode = "auto";
    options->dither = "none";
    options->diff_oklab_eps.reset();
    options->debug_stats = false;
    return;
  }
  if (value == "low-bandwidth") {
    applyPipeline("luminance", options);
    options->style = "none";
    options->render_mode = "text";
    options->structure_overlay = "auto";
    options->glyph_features = "overlap";
    options->max_fps = 12.0;
    options->fps.reset();
    options->fit = true;
    options->color_mode = "16";
    options->dither = "none";
    options->diff_oklab_eps = 0.02;
    options->line_ligatures = false;
    options->debug_stats = false;
    return;
  }
  if (value == "export") {
    applyPipeline("structure", options);
    options->style = "none";
    options->render_mode = "text";
    options->structure_overlay = "auto";
    options->glyph_features = "hog";
    options->max_fps.reset();
    options->fps.reset();
    options->fit = false;
    options->color_mode = "truecolor";
    options->dither = "none";
    options->diff_oklab_eps = 0.0;
    options->debug_stats = false;
  }
}

std::optional<int> parsePositiveInt(std::string_view value) {
  int parsed = 0;
  const auto* first = value.data();
  const auto* last = value.data() + value.size();
  const auto result = std::from_chars(first, last, parsed);
  if (result.ec != std::errc{} || result.ptr != last || parsed <= 0) {
    return std::nullopt;
  }
  return parsed;
}

std::optional<int> parseNonNegativeInt(std::string_view value) {
  int parsed = 0;
  const auto* first = value.data();
  const auto* last = value.data() + value.size();
  const auto result = std::from_chars(first, last, parsed);
  if (result.ec != std::errc{} || result.ptr != last || parsed < 0) {
    return std::nullopt;
  }
  return parsed;
}

std::optional<int64_t> parseNonNegativeInt64(std::string_view value) {
  int64_t parsed = 0;
  const auto* first = value.data();
  const auto* last = value.data() + value.size();
  const auto result = std::from_chars(first, last, parsed);
  if (result.ec != std::errc{} || result.ptr != last || parsed < 0) {
    return std::nullopt;
  }
  return parsed;
}

std::optional<double> parsePositiveDouble(std::string_view value, bool allow_zero) {
  std::string copy(value);
  char* end = nullptr;
  const double parsed = std::strtod(copy.c_str(), &end);
  if (end != copy.c_str() + copy.size() || !std::isfinite(parsed)) {
    return std::nullopt;
  }
  if (allow_zero ? parsed < 0.0 : parsed <= 0.0) {
    return std::nullopt;
  }
  return parsed;
}

std::optional<int64_t> parseTimestampUs(std::string_view value) {
  const auto first_colon = value.find(':');
  if (first_colon == std::string_view::npos) {
    return std::nullopt;
  }
  const auto second_colon = value.find(':', first_colon + 1);
  if (second_colon == std::string_view::npos || value.find(':', second_colon + 1) != std::string_view::npos) {
    return std::nullopt;
  }
  const auto hours = parseNonNegativeInt64(value.substr(0, first_colon));
  const auto minutes = parseNonNegativeInt64(value.substr(first_colon + 1, second_colon - first_colon - 1));
  std::string_view seconds_part = value.substr(second_colon + 1);
  if (!hours.has_value() || !minutes.has_value() || *minutes > 59 || seconds_part.empty()) {
    return std::nullopt;
  }
  int64_t micros = 0;
  if (const auto dot = seconds_part.find('.'); dot != std::string_view::npos) {
    std::string_view fractional = seconds_part.substr(dot + 1);
    seconds_part = seconds_part.substr(0, dot);
    if (fractional.empty() || fractional.size() > 6) {
      return std::nullopt;
    }
    for (char ch : fractional) {
      if (ch < '0' || ch > '9') {
        return std::nullopt;
      }
      micros = (micros * 10) + (ch - '0');
    }
    for (std::size_t i = fractional.size(); i < 6; ++i) {
      micros *= 10;
    }
  }
  const auto seconds = parseNonNegativeInt64(seconds_part);
  if (!seconds.has_value() || *seconds > 59) {
    return std::nullopt;
  }
  return (((*hours * 60) + *minutes) * 60 + *seconds) * 1000000 + micros;
}

bool parseDogSigma(std::string_view value, CliOptions* options) {
  const auto comma = value.find(',');
  if (comma == std::string_view::npos) {
    const auto parsed = parsePositiveDouble(value, true);
    if (!parsed.has_value()) {
      return false;
    }
    options->dog_sigma = *parsed;
    options->dog_sigma2.reset();
    return true;
  }

  const auto sigma1 = parsePositiveDouble(value.substr(0, comma), false);
  const auto sigma2 = parsePositiveDouble(value.substr(comma + 1), false);
  if (!sigma1.has_value() || !sigma2.has_value() || *sigma2 <= *sigma1) {
    return false;
  }
  options->dog_sigma = *sigma1;
  options->dog_sigma2 = *sigma2;
  return true;
}

void applyPipeline(std::string_view value, CliOptions* options) {
  options->pipeline = std::string(value);
  if (value == "halfblock") {
    options->mode = "halfblock";
    return;
  }
  if (value == "blocks") {
    options->mode = "blocks";
    return;
  }
  if (value == "octant") {
    options->mode = "octant";
    return;
  }
  if (value == "sextant") {
    options->mode = "sextant";
    return;
  }
  if (value == "braille") {
    options->mode = "braille";
    return;
  }
  options->mode = std::string(value);
}

std::string_view stripFlagValue(std::string_view arg, std::string_view* value) {
  const auto equals = arg.find('=');
  if (equals == std::string_view::npos) {
    *value = {};
    return arg;
  }
  *value = arg.substr(equals + 1);
  return arg.substr(0, equals);
}

std::optional<std::string_view> readValue(int argc, char** argv, int* index, std::string_view flag, std::string_view inline_value, std::string* error) {
  if (!inline_value.empty()) {
    return inline_value;
  }
  if (*index + 1 >= argc) {
    *error = "missing value for " + std::string(flag);
    return std::nullopt;
  }
  ++(*index);
  return std::string_view(argv[*index]);
}

std::string_view trim(std::string_view value) {
  while (!value.empty() && (value.front() == ' ' || value.front() == '\t' || value.front() == '\r')) {
    value.remove_prefix(1);
  }
  while (!value.empty() && (value.back() == ' ' || value.back() == '\t' || value.back() == '\r')) {
    value.remove_suffix(1);
  }
  return value;
}

std::string unquote(std::string_view value) {
  value = trim(value);
  if (value.size() >= 2 && ((value.front() == '"' && value.back() == '"') || (value.front() == '\'' && value.back() == '\''))) {
    value.remove_prefix(1);
    value.remove_suffix(1);
  }
  return std::string(value);
}

std::optional<CliAction> earlyAction(int argc, char** argv) {
  if (argc < 2) {
    return std::nullopt;
  }
  const std::string_view arg(argv[1]);
  if (arg == "--help") {
    return CliAction::Help;
  }
  if (arg == "--version") {
    return CliAction::Version;
  }
  return std::nullopt;
}

struct ProfileSelection {
  std::optional<std::string> name;
  std::string error;
};

ProfileSelection findProfileSelection(int argc, char** argv) {
  ProfileSelection selection;
  for (int index = 1; index < argc; ++index) {
    const std::string_view argument(argv[index]);
    if (argument == "--") {
      break;
    }
    if (!argument.starts_with("--")) {
      continue;
    }
    std::string_view inline_value;
    const std::string_view flag = stripFlagValue(argument, &inline_value);
    if (flag != "--profile") {
      continue;
    }
    std::string_view value = inline_value;
    if (value.empty()) {
      if (index + 1 >= argc) {
        selection.error = "missing value for --profile";
        return selection;
      }
      value = argv[++index];
    }
    if (!isProfileName(value)) {
      selection.error = "invalid value for --profile: " + std::string(value) +
                        "; expected live, structure, low-bandwidth, or export";
      return selection;
    }
    if (selection.name.has_value()) {
      selection.error = "duplicate flag: --profile";
      return selection;
    }
    selection.name = std::string(value);
  }
  return selection;
}

std::optional<std::filesystem::path> defaultConfigPath() {
  if (const char* xdg_config_home = std::getenv("XDG_CONFIG_HOME"); xdg_config_home != nullptr && *xdg_config_home != '\0') {
    return std::filesystem::path(xdg_config_home) / "strok" / "config";
  }
  if (const char* home = std::getenv("HOME"); home != nullptr && *home != '\0') {
    return std::filesystem::path(home) / ".config" / "strok" / "config";
  }
  return std::nullopt;
}

bool isConfigBooleanKey(std::string_view key) {
  return isOneOf(key, {"fit", "loop", "mirror", "gpu", "mono", "debug-stats", "ramp-sort", "line-ligatures", "reconnect"});
}

std::optional<bool> parseConfigBool(std::string_view value) {
  value = trim(value);
  if (isOneOf(value, {"true", "yes", "on", "1"})) {
    return true;
  }
  if (isOneOf(value, {"false", "no", "off", "0"})) {
    return false;
  }
  return std::nullopt;
}

std::string normalizeConfigKey(std::string_view key) {
  key = trim(key);
  if (key.starts_with("--")) {
    key.remove_prefix(2);
  }
  std::string normalized(key);
  for (char& ch : normalized) {
    if (ch == '_') {
      ch = '-';
    }
  }
  return normalized;
}

bool appendConfigArg(std::vector<std::string>* args, std::string_view key_view, std::string_view value_view, std::string* error) {
  const std::string key = normalizeConfigKey(key_view);
  const std::string value = unquote(value_view);
  if (key.empty()) {
    *error = "empty config key";
    return false;
  }
  if (isConfigBooleanKey(key)) {
    const auto parsed = parseConfigBool(value);
    if (!parsed.has_value()) {
      *error = "invalid boolean for " + key + ": " + value;
      return false;
    }
    args->push_back(*parsed ? "--" + key : "--no-" + key);
    return true;
  }
  args->push_back("--" + key);
  args->push_back(value);
  return true;
}

CliParseResult parseArgsFromArgv(int argc, char** argv, CliOptions defaults) {
  CliParseResult result;
  result.options = defaults;
  bool style_seen = false;

  for (int i = 1; i < argc; ++i) {
    std::string_view arg(argv[i]);
    if (arg == "--") {
      if (i + 1 >= argc) {
        break;
      }
      if (result.options.input.has_value()) {
        result.error = "unexpected argument: " + std::string(argv[i + 1]);
        return result;
      }
      result.options.input = argv[++i];
      if (i + 1 < argc) {
        result.error = "unexpected argument: " + std::string(argv[i + 1]);
      }
      return result;
    }

    if (!arg.starts_with("--")) {
      if (result.options.input.has_value()) {
        result.error = "unexpected argument: " + std::string(arg);
        return result;
      }
      result.options.input = std::string(arg);
      continue;
    }

    std::string_view inline_value;
    const std::string_view flag = stripFlagValue(arg, &inline_value);

    if (flag == "--help") {
      result.action = CliAction::Help;
      return result;
    }
    if (flag == "--version") {
      result.action = CliAction::Version;
      return result;
    }
    if (flag == "--doctor") {
      result.action = CliAction::Doctor;
      continue;
    }
    if (flag == "--fit") {
      result.options.fit = true;
      continue;
    }
    if (flag == "--no-fit") {
      result.options.fit = false;
      continue;
    }
    if (flag == "--loop") {
      result.options.loop = true;
      continue;
    }
    if (flag == "--no-loop") {
      result.options.loop = false;
      continue;
    }
    if (flag == "--reconnect") {
      result.options.reconnect = true;
      continue;
    }
    if (flag == "--no-reconnect") {
      result.options.reconnect = false;
      continue;
    }
    if (flag == "--mirror") {
      result.options.mirror = true;
      continue;
    }
    if (flag == "--no-mirror") {
      result.options.mirror = false;
      continue;
    }
    if (flag == "--gpu") {
      result.options.gpu = true;
      continue;
    }
    if (flag == "--no-gpu") {
      result.options.gpu = false;
      continue;
    }
    if (flag == "--line-ligatures") {
      result.options.line_ligatures = true;
      continue;
    }
    if (flag == "--no-line-ligatures") {
      result.options.line_ligatures = false;
      continue;
    }
    if (flag == "--debug-stats") {
      result.options.debug_stats = true;
      continue;
    }
    if (flag == "--no-debug-stats") {
      result.options.debug_stats = false;
      continue;
    }
    if (flag == "--ramp-sort") {
      result.options.ramp_sort = true;
      continue;
    }
    if (flag == "--no-ramp-sort") {
      result.options.ramp_sort = false;
      continue;
    }
    if (flag == "--mono") {
      result.options.color_mode = "mono";
      continue;
    }
    if (flag == "--no-mono") {
      result.options.color_mode = "auto";
      continue;
    }

    if (!isOneOf(flag, {
          "--width",
          "--height",
          "--input",
          "--profile",
          "--cell-aspect",
          "--fps",
          "--max-fps",
          "--input-open-timeout",
          "--read-timeout",
          "--rtsp-transport",
          "--reconnect-backoff",
          "--mode",
          "--style",
          "--render-mode",
          "--structure-overlay",
          "--pipeline",
          "--font",
          "--glyph-features",
          "--color-mode",
          "--color",
          "--charset",
          "--edge-threshold",
          "--edge-strength",
          "--dog-sigma",
          "--dog-threshold",
          "--etf-iters",
          "--lic-length",
          "--posterize",
          "--contrast",
          "--glyph-stickiness",
          "--orient-stickiness",
          "--temporal-supersample",
          "--dither",
          "--diff-oklab-eps",
          "--bandwidth-cap",
          "--input-keys",
          "--log",
          "--ffmpeg-log",
          "--metrics-jsonl",
          "--export",
          "--still",
          "--still-at",
          "--graph",
          "--split",
          "--grid",
          "--plot",
          "--overlay",
          "--overlay-alpha",
          "--overlay-depth-threshold",
          "--captions",
          "--plot-window",
          "--plot-rate",
          "--scene-camera",
          "--caps",
          "--dump-frame",
          "--dump-png",
        })) {
      result.error = "unknown flag: " + std::string(flag);
      return result;
    }

    const auto value = readValue(argc, argv, &i, flag, inline_value, &result.error);
    if (!value.has_value()) {
      return result;
    }

    if (flag == "--profile") {
      if (!isProfileName(*value)) {
        result.error = "invalid value for --profile: " + std::string(*value) +
                       "; expected live, structure, low-bandwidth, or export";
        return result;
      }
      result.options.profile = std::string(*value);
    } else if (flag == "--input") {
      if (result.options.input.has_value()) {
        result.error = "unexpected argument: " + std::string(*value);
        return result;
      }
      result.options.input = std::string(*value);
    } else if (flag == "--width") {
      const auto parsed = parsePositiveInt(*value);
      if (!parsed.has_value()) {
        result.error = "invalid value for --width: " + std::string(*value);
        return result;
      }
      result.options.width = *parsed;
    } else if (flag == "--height") {
      const auto parsed = parsePositiveInt(*value);
      if (!parsed.has_value()) {
        result.error = "invalid value for --height: " + std::string(*value);
        return result;
      }
      result.options.height = *parsed;
    } else if (flag == "--cell-aspect") {
      const auto parsed = parsePositiveDouble(*value, false);
      if (!parsed.has_value()) {
        result.error = "invalid value for --cell-aspect: " + std::string(*value);
        return result;
      }
      result.options.cell_aspect = *parsed;
    } else if (flag == "--fps") {
      const auto parsed = parsePositiveDouble(*value, false);
      if (!parsed.has_value()) {
        result.error = "invalid value for --fps: " + std::string(*value);
        return result;
      }
      result.options.fps = *parsed;
    } else if (flag == "--max-fps") {
      const auto parsed = parsePositiveDouble(*value, false);
      if (!parsed.has_value()) {
        result.error = "invalid value for --max-fps: " + std::string(*value);
        return result;
      }
      result.options.max_fps = *parsed;
    } else if (flag == "--input-open-timeout") {
      const auto parsed = parseNonNegativeInt(*value);
      if (!parsed.has_value() || *parsed > 300000) {
        result.error = "invalid value for --input-open-timeout: expected milliseconds in 0..300000";
        return result;
      }
      result.options.input_open_timeout_ms = *parsed;
    } else if (flag == "--read-timeout") {
      const auto parsed = parseNonNegativeInt(*value);
      if (!parsed.has_value() || *parsed > 300000) {
        result.error = "invalid value for --read-timeout: expected milliseconds in 0..300000";
        return result;
      }
      result.options.read_timeout_ms = *parsed;
    } else if (flag == "--rtsp-transport") {
      if (!isOneOf(*value, {"auto", "tcp", "udp"})) {
        result.error = "invalid value for --rtsp-transport: expected auto, tcp, or udp";
        return result;
      }
      result.options.rtsp_transport = std::string(*value);
    } else if (flag == "--reconnect-backoff") {
      const auto parsed = parsePositiveInt(*value);
      if (!parsed.has_value() || *parsed > 60000) {
        result.error = "invalid value for --reconnect-backoff: expected milliseconds in 1..60000";
        return result;
      }
      result.options.reconnect_backoff_ms = *parsed;
    } else if (flag == "--mode") {
      if (!isOneOf(*value, {"auto", "luminance", "structure", "halfblock", "blocks", "octant", "sextant", "braille"})) {
        result.error = "invalid value for --mode: " + std::string(*value);
        return result;
      }
      result.options.mode = std::string(*value);
    } else if (flag == "--style") {
      if (style_seen) {
        result.error = "duplicate flag: --style";
        return result;
      }
      if (!isOneOf(*value, {"none", "painterly", "hatch", "stipple", "flow", "cell-shade"})) {
        result.error = "invalid value for --style: " + std::string(*value);
        return result;
      }
      result.options.style = std::string(*value);
      style_seen = true;
    } else if (flag == "--render-mode") {
      if (!isOneOf(*value, {"auto", "text", "pixel", "hybrid"})) {
        result.error = "invalid value for --render-mode: " + std::string(*value);
        return result;
      }
      result.options.render_mode = std::string(*value);
    } else if (flag == "--structure-overlay") {
      if (!isOneOf(*value, {"auto", "on", "off"})) {
        result.error = "invalid value for --structure-overlay: " + std::string(*value);
        return result;
      }
      result.options.structure_overlay = std::string(*value);
    } else if (flag == "--pipeline") {
      if (!isOneOf(*value, {"auto", "luminance", "structure", "halfblock", "blocks", "octant", "sextant", "braille"})) {
        result.error = "invalid value for --pipeline: " + std::string(*value);
        return result;
      }
      applyPipeline(*value, &result.options);
    } else if (flag == "--font") {
      if (value->empty()) {
        result.error = "invalid value for --font: expected path";
        return result;
      }
      result.options.font_path = std::string(*value);
    } else if (flag == "--glyph-features") {
      if (!isOneOf(*value, {"overlap", "hog", "sdf"})) {
        result.error = "invalid value for --glyph-features: " + std::string(*value);
        return result;
      }
      result.options.glyph_features = std::string(*value);
    } else if (flag == "--color-mode" || flag == "--color") {
      if (!isOneOf(*value, {"auto", "truecolor", "256", "16", "mono"})) {
        result.error = "invalid value for " + std::string(flag) + ": " + std::string(*value);
        return result;
      }
      result.options.color_mode = std::string(*value);
    } else if (flag == "--charset") {
      if (!isValidCharset(*value)) {
        result.error = "invalid value for --charset: expected non-empty UTF-8";
        return result;
      }
      result.options.charset = std::string(*value);
    } else if (flag == "--edge-threshold") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value()) {
        result.error = "invalid value for --edge-threshold: " + std::string(*value);
        return result;
      }
      result.options.edge_threshold = *parsed;
    } else if (flag == "--edge-strength") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value()) {
        result.error = "invalid value for --edge-strength: " + std::string(*value);
        return result;
      }
      result.options.edge_strength = *parsed;
    } else if (flag == "--dog-sigma") {
      if (!parseDogSigma(*value, &result.options)) {
        result.error = "invalid value for --dog-sigma: " + std::string(*value);
        return result;
      }
    } else if (flag == "--dog-threshold") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value()) {
        result.error = "invalid value for --dog-threshold: " + std::string(*value);
        return result;
      }
      result.options.dog_threshold = *parsed;
    } else if (flag == "--etf-iters") {
      const auto parsed = parseNonNegativeInt(*value);
      if (!parsed.has_value() || *parsed > 16) {
        result.error = "invalid value for --etf-iters: " + std::string(*value);
        return result;
      }
      result.options.etf_iters = *parsed;
    } else if (flag == "--lic-length") {
      const auto parsed = parsePositiveInt(*value);
      if (!parsed.has_value() || *parsed > 64) {
        result.error = "invalid value for --lic-length: " + std::string(*value);
        return result;
      }
      result.options.lic_length = *parsed;
    } else if (flag == "--posterize") {
      const auto parsed = parsePositiveInt(*value);
      if (!parsed.has_value() || *parsed < 2 || *parsed > 64) {
        result.error = "invalid value for --posterize: " + std::string(*value);
        return result;
      }
      result.options.posterize = *parsed;
    } else if (flag == "--contrast") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value()) {
        result.error = "invalid value for --contrast: " + std::string(*value);
        return result;
      }
      result.options.contrast = *parsed;
    } else if (flag == "--glyph-stickiness") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value() || *parsed > 1.0) {
        result.error = "invalid value for --glyph-stickiness: " + std::string(*value);
        return result;
      }
      result.options.glyph_stickiness = *parsed;
    } else if (flag == "--orient-stickiness") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value() || *parsed > 3.14159265358979323846) {
        result.error = "invalid value for --orient-stickiness: " + std::string(*value);
        return result;
      }
      result.options.orient_stickiness = *parsed;
    } else if (flag == "--temporal-supersample") {
      const auto parsed = parsePositiveInt(*value);
      if (!parsed.has_value() || *parsed > 8) {
        result.error = "invalid value for --temporal-supersample: " + std::string(*value);
        return result;
      }
      result.options.temporal_supersample = *parsed;
    } else if (flag == "--dither") {
      if (!isOneOf(*value, {"none", "ordered", "fs"})) {
        result.error = "invalid value for --dither: " + std::string(*value);
        return result;
      }
      result.options.dither = std::string(*value);
    } else if (flag == "--diff-oklab-eps") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value()) {
        result.error = "invalid value for --diff-oklab-eps: " + std::string(*value);
        return result;
      }
      result.options.diff_oklab_eps = *parsed;
    } else if (flag == "--bandwidth-cap") {
      const auto parsed = parsePositiveDouble(*value, false);
      if (!parsed.has_value()) {
        result.error = "invalid value for --bandwidth-cap: " + std::string(*value);
        return result;
      }
      result.options.bandwidth_cap_mb_s = *parsed;
    } else if (flag == "--input-keys") {
      if (value->empty()) {
        result.error = "invalid value for --input-keys: expected key bytes";
        return result;
      }
      result.options.input_keys = std::string(*value);
    } else if (flag == "--log") {
      result.options.log_file = std::string(*value);
    } else if (flag == "--ffmpeg-log") {
      if (!isFfmpegLogLevel(*value)) {
        result.error = "invalid value for --ffmpeg-log: expected off, error, warning, info, debug, or trace";
        return result;
      }
      result.options.ffmpeg_log_level = std::string(*value);
    } else if (flag == "--metrics-jsonl") {
      if (value->empty()) {
        result.error = "invalid value for --metrics-jsonl: expected output path";
        return result;
      }
      result.options.metrics_jsonl_file = std::string(*value);
    } else if (flag == "--export") {
      result.options.export_file = std::string(*value);
    } else if (flag == "--still") {
      if (value->empty()) {
        result.error = "invalid value for --still: expected output path";
        return result;
      }
      result.options.still_file = std::string(*value);
    } else if (flag == "--still-at") {
      const auto parsed = parseTimestampUs(*value);
      if (!parsed.has_value()) {
        result.error = "invalid value for --still-at: expected HH:MM:SS[.ffffff]";
        return result;
      }
      result.options.still_at_us = *parsed;
    } else if (flag == "--graph") {
      if (value->empty()) {
        result.error = "invalid value for --graph: expected dump or yaml file";
        return result;
      }
      result.options.graph = std::string(*value);
    } else if (flag == "--split") {
      if (!parseSplitSpec(*value).has_value()) {
        result.error = "invalid value for --split: expected LEFT:RIGHT";
        return result;
      }
      result.options.split = std::string(*value);
    } else if (flag == "--grid") {
      if (!parseImageGridSpec(*value).has_value()) {
        result.error = "invalid value for --grid: expected CxR";
        return result;
      }
      result.options.grid = std::string(*value);
    } else if (flag == "--plot") {
      if (!parsePlotKind(*value).has_value()) {
        result.error = "invalid value for --plot: " + std::string(*value);
        return result;
      }
      result.options.plot = std::string(*value);
    } else if (flag == "--overlay") {
      if (value->empty()) {
        result.error = "invalid value for --overlay: expected path or source";
        return result;
      }
      result.options.overlay = std::string(*value);
    } else if (flag == "--overlay-alpha") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value() || *parsed > 1.0) {
        result.error = "invalid value for --overlay-alpha: " + std::string(*value);
        return result;
      }
      result.options.overlay_alpha = *parsed;
    } else if (flag == "--overlay-depth-threshold") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value()) {
        result.error = "invalid value for --overlay-depth-threshold: " + std::string(*value);
        return result;
      }
      result.options.overlay_depth_threshold = *parsed;
    } else if (flag == "--captions") {
      if (value->empty()) {
        result.error = "invalid value for --captions: expected output path";
        return result;
      }
      result.options.captions_file = std::string(*value);
    } else if (flag == "--plot-window") {
      const auto parsed = parsePositiveInt(*value);
      if (!parsed.has_value()) {
        result.error = "invalid value for --plot-window: " + std::string(*value);
        return result;
      }
      result.options.plot_window = *parsed;
    } else if (flag == "--plot-rate") {
      const auto parsed = parsePositiveDouble(*value, false);
      if (!parsed.has_value()) {
        result.error = "invalid value for --plot-rate: " + std::string(*value);
        return result;
      }
      result.options.plot_rate_hz = *parsed;
    } else if (flag == "--scene-camera") {
      if (!parseSceneCameraPreset(*value).has_value()) {
        result.error = "invalid value for --scene-camera: " + std::string(*value);
        return result;
      }
      result.options.scene_camera = std::string(*value);
    } else if (flag == "--caps") {
      if (value->empty()) {
        result.error = "invalid value for --caps: expected dump or override spec";
        return result;
      }
      result.options.caps = std::string(*value);
    } else if (flag == "--dump-frame") {
      const auto parsed = parsePositiveInt(*value);
      if (!parsed.has_value()) {
        result.error = "invalid value for --dump-frame: " + std::string(*value);
        return result;
      }
      result.options.dump_frame = *parsed;
    } else if (flag == "--dump-png") {
      result.options.dump_png = std::string(*value);
    }
  }

  return result;
}

CliParseResult loadConfigDefaults() {
  CliParseResult result;
  const auto config_path = defaultConfigPath();
  if (!config_path.has_value() || !std::filesystem::exists(*config_path)) {
    return result;
  }
  result.config_path = *config_path;
  std::ifstream input(*config_path);
  if (!input) {
    result.error = "could not read config: " + config_path->string();
    return result;
  }

  std::vector<std::string> args {"strok-config"};
  std::optional<std::string> profile;
  std::string line;
  int line_number = 0;
  while (std::getline(input, line)) {
    ++line_number;
    std::string_view view = trim(line);
    if (view.empty() || view.front() == '#') {
      continue;
    }
    const auto equals = view.find('=');
    if (equals == std::string_view::npos) {
      result.error = "invalid config line " + std::to_string(line_number) + ": expected key=value";
      return result;
    }
    const std::string key = normalizeConfigKey(view.substr(0, equals));
    if (key == "profile") {
      const std::string value = unquote(view.substr(equals + 1));
      if (!isProfileName(value)) {
        result.error = "invalid config line " + std::to_string(line_number) +
                       ": invalid profile: expected live, structure, low-bandwidth, or export";
        return result;
      }
      if (profile.has_value()) {
        result.error = "invalid config line " + std::to_string(line_number) + ": duplicate profile";
        return result;
      }
      profile = value;
      continue;
    }
    std::string error;
    if (!appendConfigArg(&args, view.substr(0, equals), view.substr(equals + 1), &error)) {
      result.error = "invalid config line " + std::to_string(line_number) + ": " + error;
      return result;
    }
  }

  std::vector<char*> argv;
  argv.reserve(args.size());
  for (std::string& arg : args) {
    argv.push_back(arg.data());
  }
  CliOptions config_defaults;
  if (profile.has_value()) {
    applyProfile(*profile, &config_defaults);
    config_defaults.profile = profile;
  }
  result = parseArgsFromArgv(static_cast<int>(argv.size()), argv.data(), std::move(config_defaults));
  result.config_path = *config_path;
  if (!result.error.empty()) {
    result.error = "invalid config " + config_path->string() + ": " + result.error;
  }
  return result;
}

}  // namespace

CliParseResult parseArgs(int argc, char** argv) {
  if (const auto action = earlyAction(argc, argv); action.has_value()) {
    return CliParseResult{.action = *action};
  }
  CliParseResult defaults = loadConfigDefaults();
  if (!defaults.error.empty()) {
    return defaults;
  }
  const ProfileSelection profile = findProfileSelection(argc, argv);
  if (!profile.error.empty()) {
    return CliParseResult{.options = defaults.options, .config_path = defaults.config_path, .error = profile.error};
  }
  CliOptions options = defaults.options;
  if (profile.name.has_value()) {
    applyProfile(*profile.name, &options);
    options.profile = profile.name;
  }
  CliParseResult result = parseArgsFromArgv(argc, argv, std::move(options));
  result.config_path = defaults.config_path;
  if (result.error.empty() && result.options.ffmpeg_log_level != "off" && !result.options.log_file.has_value()) {
    result.error = "--ffmpeg-log requires --log FILE";
  }
  if (result.error.empty() && result.options.metrics_jsonl_file.has_value() &&
      (result.options.export_file.has_value() || result.options.still_file.has_value() ||
       result.options.captions_file.has_value() || result.options.dump_frame.has_value() ||
       result.options.dump_png.has_value())) {
    result.error = "--metrics-jsonl is only supported during terminal playback";
  }
  return result;
}

std::string helpText(std::string_view program_name) {
  std::ostringstream out;
  out << "usage: " << program_name << " [options] [<input>]\n"
      << "\n"
      << "options:\n";
  constexpr std::size_t kHelpSyntaxWidth = 31;
  for (const CliOptionSpec& option : cliOptionSpecs()) {
    out << "  " << option.syntax;
    if (!option.description.empty()) {
      if (option.syntax.size() < kHelpSyntaxWidth) {
        out << std::string(kHelpSyntaxWidth - option.syntax.size(), ' ');
      } else {
        out << ' ';
      }
      out << option.description;
    }
    out << '\n';
  }
  return out.str();
}

}  // namespace strok
