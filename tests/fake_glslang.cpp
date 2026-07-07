#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>

int main(int argc, char** argv) {
  std::string out;
  std::string input;
  std::string stage;
  std::string entry;
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "-o" && i + 1 < argc) {
      out = argv[++i];
    } else if (arg == "-S" && i + 1 < argc) {
      stage = argv[++i];
    } else if (arg == "-e" && i + 1 < argc) {
      entry = argv[++i];
    } else if (!arg.empty() && arg[0] == '-') {
      continue;
    } else {
      input = arg;
    }
  }

  if (stage != "frag") {
    return 42;
  }
  if (entry != "mainImage") {
    return 43;
  }
  if (out.empty()) {
    return 44;
  }
  if (input.empty()) {
    return 45;
  }

  if (const char* seen = std::getenv("CONTOURTTY_FAKE_GLSLANG_SEEN"); seen != nullptr && *seen != '\0') {
    std::error_code ec;
    std::filesystem::copy_file(input, seen, std::filesystem::copy_options::overwrite_existing, ec);
    if (ec) {
      return 46;
    }
  }

  std::ofstream output(out, std::ios::binary);
  output << "SPV0fake";
  return output ? 0 : 47;
}
