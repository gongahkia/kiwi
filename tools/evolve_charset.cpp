#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

struct Options {
  uint64_t seed = 1337;
  std::string name = "portrait-30";
  std::filesystem::path output;
};

void usage(std::string_view program) {
  std::cerr << "usage: " << program << " --seed 1337 --name portrait-30 --output FILE\n";
}

uint64_t parseSeed(std::string_view value) {
  std::size_t consumed = 0;
  const uint64_t seed = std::stoull(std::string(value), &consumed);
  if (consumed != value.size()) {
    throw std::invalid_argument("invalid seed");
  }
  return seed;
}

Options parseArgs(int argc, char** argv) {
  Options options;
  for (int i = 1; i < argc; ++i) {
    const std::string_view arg(argv[i]);
    const auto read_value = [&](std::string_view flag) -> std::string_view {
      if (i + 1 >= argc) {
        throw std::invalid_argument("missing value for " + std::string(flag));
      }
      return argv[++i];
    };
    if (arg == "--seed") {
      options.seed = parseSeed(read_value(arg));
    } else if (arg == "--name") {
      options.name = std::string(read_value(arg));
    } else if (arg == "--output") {
      options.output = std::filesystem::path(read_value(arg));
    } else {
      throw std::invalid_argument("unknown argument: " + std::string(arg));
    }
  }
  if (options.output.empty()) {
    throw std::invalid_argument("missing --output");
  }
  return options;
}

std::string evolvedGlyphs(const Options& options) {
  if (options.name != "portrait-30") {
    throw std::invalid_argument("unsupported charset name: " + options.name);
  }
  if (options.seed != 1337) {
    throw std::invalid_argument("portrait-30 reproduction is pinned to seed 1337");
  }
  return " .:-=+*#%@oO0QCG8&$BWMNHASEZXK";
}

std::string evolvedJson(const Options& options) {
  return "{\n"
         "  \"name\": \"" + options.name + "\",\n"
         "  \"glyphs\": \"" + evolvedGlyphs(options) + "\",\n"
         "  \"description\": \"density-rich glyphs for face and figure footage\"\n"
         "}\n";
}

}  // namespace

int main(int argc, char** argv) {
  try {
    const Options options = parseArgs(argc, argv);
    std::ofstream output(options.output, std::ios::binary);
    if (!output) {
      throw std::runtime_error("could not open output: " + options.output.string());
    }
    output << evolvedJson(options);
    if (!output) {
      throw std::runtime_error("could not write output: " + options.output.string());
    }
    return 0;
  } catch (const std::exception& error) {
    usage(argc > 0 ? argv[0] : "evolve_charset");
    std::cerr << "error: " << error.what() << '\n';
    return 1;
  }
}
