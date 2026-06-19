#include "cli.hpp"

#include "glyph_ramp.hpp"

#include <charconv>
#include <cstdlib>
#include <sstream>
#include <string>
#include <string_view>

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

}  // namespace

CliParseResult parseArgs(int argc, char** argv) {
  CliParseResult result;

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
    if (flag == "--loop") {
      result.options.loop = true;
      continue;
    }
    if (flag == "--gpu") {
      result.options.gpu = true;
      continue;
    }

    if (!isOneOf(flag, {
          "--width",
          "--height",
          "--cell-aspect",
          "--fps",
          "--max-fps",
          "--mode",
          "--color-mode",
          "--color",
          "--charset",
          "--edge-threshold",
          "--dog-sigma",
          "--contrast",
          "--dither",
          "--log",
          "--export",
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

    if (flag == "--width") {
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
      if (!isOneOf(*value, {"luminance", "structure", "halfblock"})) {
        result.error = "invalid value for --mode: " + std::string(*value);
        return result;
      }
      result.options.mode = std::string(*value);
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
    } else if (flag == "--dog-sigma") {
      const auto parsed = parsePositiveDouble(*value, true);
      if (!parsed.has_value()) {
        result.error = "invalid value for --dog-sigma: " + std::string(*value);
        return result;
      }
      result.options.dog_sigma = *parsed;
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

std::string helpText(std::string_view program_name) {
  std::ostringstream out;
  out << "usage: " << program_name << " [options] [<input>]\n"
      << "\n"
      << "options:\n"
      << "  --help                         show this help\n"
      << "  --version                      show version\n"
      << "  --width N                      target terminal columns\n"
      << "  --height N                     target terminal rows\n"
      << "  --cell-aspect N                terminal cell width/height ratio\n"
      << "  --fit                          fit output to terminal\n"
      << "  --fps N                        override source fps\n"
      << "  --max-fps N                    cap render fps\n"
      << "  --mode {luminance|structure|halfblock}\n"
      << "  --color-mode {auto|truecolor|256|16|mono}\n"
      << "  --color {auto|truecolor|256|16|mono}\n"
      << "  --charset NAME|string          glyph preset or custom glyph string\n"
      << "  --edge-threshold N             structure edge threshold\n"
      << "  --dog-sigma N                  difference-of-gaussians sigma\n"
      << "  --contrast N                   structure contrast adjustment\n"
      << "  --dither {none|ordered|fs}     color dithering mode\n"
      << "  --loop                         loop input\n"
      << "  --log FILE                     write diagnostics to file\n"
      << "  --gpu                          request gpu analysis path\n"
      << "  --export FILE                  render to output file\n"
      << "  --dump-frame N                 dump decoded frame N for diagnostics\n"
      << "  --dump-png FILE                write dumped frame as RGB PNG\n";
  return out.str();
}

}  // namespace contourtty
