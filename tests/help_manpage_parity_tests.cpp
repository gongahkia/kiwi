#include "cli.hpp"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#ifndef STROK_SOURCE_DIR
#define STROK_SOURCE_DIR "."
#endif

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

std::vector<std::string> helpOptionLines() {
  std::istringstream input(strok::helpText("strok"));
  std::vector<std::string> lines;
  std::string line;
  bool in_options = false;
  while (std::getline(input, line)) {
    if (line == "options:") {
      in_options = true;
      continue;
    }
    if (in_options && line.starts_with("  --")) {
      lines.push_back(line);
    }
  }
  return lines;
}

std::vector<std::string> manOptionLines(const std::string& man) {
  std::istringstream input(man);
  std::vector<std::string> lines;
  std::string line;
  bool in_options = false;
  while (std::getline(input, line)) {
    if (line == "options:") {
      in_options = true;
      continue;
    }
    if (in_options && line == ".fi") {
      break;
    }
    if (in_options && line.starts_with("  --")) {
      lines.push_back(line);
    }
  }
  return lines;
}

std::string readFile(const std::filesystem::path& path) {
  std::ifstream input(path);
  expect(static_cast<bool>(input), "man page opens");
  std::ostringstream buffer;
  buffer << input.rdbuf();
  return buffer.str();
}

}  // namespace

int main() {
  const std::string man = readFile(std::filesystem::path(STROK_SOURCE_DIR) / "docs" / "strok.1");
  const std::vector<std::string> options = helpOptionLines();
  const std::vector<std::string> man_options = manOptionLines(man);
  expect(!options.empty(), "help exposes options");
  for (const std::string& line : options) {
    if (man.find(line) == std::string::npos) {
      std::cerr << "missing manpage option: " << line << '\n';
      return 1;
    }
  }
  for (const std::string& line : man_options) {
    if (std::find(options.begin(), options.end(), line) == options.end()) {
      std::cerr << "missing help option: " << line << '\n';
      return 1;
    }
  }
}
