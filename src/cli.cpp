#include "cli.hpp"

#include "glyph_ramp.hpp"

#include <charconv>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace contourtty {
namespace {

bool isOneOf(std::string_view value, std::initializer_list<std::string_view> allowed) {
  for (const auto allowed_value : allowed) {
    if (value == allowed_value) {
      return true;
    }
  }
  return false;
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

std::optional<double> parsePositiveDouble(std::string_view value, bool allow_zero) {
  std::string copy(value);
  char* end = nullptr;
  const double parsed = std::strtod(copy.c_str(), &end);
  if (end != copy.c_str() + copy.size()) {
    return std::nullopt;
  }
  if (allow_zero ? parsed < 0.0 : parsed <= 0.0) {
    return std::nullopt;
  }
  return parsed;
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

std::optional<std::filesystem::path> defaultConfigPath() {
  if (const char* xdg_config_home = std::getenv("XDG_CONFIG_HOME"); xdg_config_home != nullptr && *xdg_config_home != '\0') {
    return std::filesystem::path(xdg_config_home) / "contourtty" / "config";
  }
  if (const char* home = std::getenv("HOME"); home != nullptr && *home != '\0') {
    return std::filesystem::path(home) / ".config" / "contourtty" / "config";
  }
  return std::nullopt;
}

bool isConfigBooleanKey(std::string_view key) {
  return isOneOf(key, {"fit", "loop", "mirror", "gpu", "mono", "debug-stats", "ramp-sort"});
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
          "--cell-aspect",
          "--fps",
          "--max-fps",
          "--mode",
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
          "--contrast",
          "--dither",
          "--log",
          "--export",
          "--graph",
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

    if (flag == "--input") {
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
    } else if (flag == "--mode") {
      if (!isOneOf(*value, {"auto", "luminance", "structure", "halfblock", "blocks", "octant", "sextant", "braille"})) {
        result.error = "invalid value for --mode: " + std::string(*value);
        return result;
      }
      result.options.mode = std::string(*value);
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
    } else if (flag == "--contrast") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value()) {
        result.error = "invalid value for --contrast: " + std::string(*value);
        return result;
      }
      result.options.contrast = *parsed;
    } else if (flag == "--dither") {
      if (!isOneOf(*value, {"none", "ordered", "fs"})) {
        result.error = "invalid value for --dither: " + std::string(*value);
        return result;
      }
      result.options.dither = std::string(*value);
    } else if (flag == "--log") {
      result.options.log_file = std::string(*value);
    } else if (flag == "--export") {
      result.options.export_file = std::string(*value);
    } else if (flag == "--graph") {
      if (!isOneOf(*value, {"dump"})) {
        result.error = "invalid value for --graph: " + std::string(*value);
        return result;
      }
      result.options.graph = std::string(*value);
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
  std::ifstream input(*config_path);
  if (!input) {
    result.error = "could not read config: " + config_path->string();
    return result;
  }

  std::vector<std::string> args {"contourtty-config"};
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
  result = parseArgsFromArgv(static_cast<int>(argv.size()), argv.data(), CliOptions{});
  if (!result.error.empty()) {
    result.error = "invalid config " + config_path->string() + ": " + result.error;
  }
  return result;
}

}  // namespace

CliParseResult parseArgs(int argc, char** argv) {
  if (const auto action = earlyAction(argc, argv); action.has_value()) {
    CliParseResult result;
    result.action = *action;
    return result;
  }
  CliParseResult defaults = loadConfigDefaults();
  if (!defaults.error.empty()) {
    return defaults;
  }
  return parseArgsFromArgv(argc, argv, defaults.options);
}

std::string helpText(std::string_view program_name) {
  std::ostringstream out;
  out << "usage: " << program_name << " [options] [<input>]\n"
      << "\n"
      << "options:\n"
      << "  --help                         show this help\n"
      << "  --version                      show version\n"
      << "  --width N                      target terminal columns\n"
      << "  --height N                     target terminal rows\n"
      << "  --input PATH|URL|cam           input path, stream URL, or camera alias\n"
      << "  --cell-aspect N                terminal cell width/height ratio\n"
      << "  --fit                          fit output to terminal\n"
      << "  --no-fit                       disable config-default fit\n"
      << "  --fps N                        override source fps\n"
      << "  --max-fps N                    cap render fps\n"
      << "  --mode {auto|luminance|structure|halfblock|blocks|octant|sextant|braille}\n"
      << "  --render-mode {auto|text|pixel|hybrid}\n"
      << "  --structure-overlay {auto|on|off}\n"
      << "  --pipeline {auto|luminance|structure|halfblock|blocks|octant|sextant|braille}\n"
      << "  --font PATH                    use FreeType font for glyph analysis/export\n"
      << "  --glyph-features {overlap|hog|sdf}\n"
      << "  --ramp-sort                    sort glyph ramp by FreeType ink density\n"
      << "  --no-ramp-sort                 disable config-default ramp sort\n"
      << "  --color-mode {auto|truecolor|256|16|mono}\n"
      << "  --color {auto|truecolor|256|16|mono}\n"
      << "  --mono                         disable color output\n"
      << "  --no-mono                      restore automatic color detection\n"
      << "  --charset NAME|string          glyph preset or custom glyph string\n"
      << "  --edge-threshold N             structure edge threshold\n"
      << "  --edge-strength N              structure edge overlay strength\n"
      << "  --dog-sigma N[,M]              difference-of-gaussians sigma pair; 0 disables\n"
      << "  --dog-threshold N              difference-of-gaussians threshold\n"
      << "  --contrast N                   structure contrast adjustment\n"
      << "  --dither {none|ordered|fs}     color dithering mode\n"
      << "  --loop                         loop input\n"
      << "  --no-loop                      disable config-default looping\n"
      << "  --mirror                       mirror camera input horizontally\n"
      << "  --no-mirror                    disable camera mirroring\n"
      << "  --log FILE                     write diagnostics to file\n"
      << "  --gpu                          request gpu analysis path\n"
      << "  --no-gpu                       disable config-default gpu request\n"
      << "  --debug-stats                  show live fps/cpu/rss diagnostics\n"
      << "  --no-debug-stats               disable config-default debug stats\n"
      << "  --graph dump                   print resolved render graph and exit\n"
      << "  --caps dump|SPEC               print or override terminal capability detection\n"
      << "  --export FILE                  render to output file\n"
      << "  --dump-frame N                 dump decoded frame N for diagnostics\n"
      << "  --dump-png FILE                write dumped frame as RGB PNG\n";
  return out.str();
}

}  // namespace contourtty
