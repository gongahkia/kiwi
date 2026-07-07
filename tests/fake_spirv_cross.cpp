#include <filesystem>
#include <fstream>
#include <string>

int main(int argc, char** argv) {
  std::string input;
  std::string out;
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--output" && i + 1 < argc) {
      out = argv[++i];
    } else if (!arg.empty() && arg[0] == '-') {
      continue;
    } else if (input.empty()) {
      input = arg;
    }
  }

  std::error_code ec;
  if (input.empty() || !std::filesystem::is_regular_file(input, ec) || std::filesystem::file_size(input, ec) == 0) {
    return 45;
  }
  if (out.empty()) {
    return 46;
  }

  std::ofstream output(out);
  output << "// msl from fake\nkernel void main0() {}\n";
  return output ? 0 : 47;
}
