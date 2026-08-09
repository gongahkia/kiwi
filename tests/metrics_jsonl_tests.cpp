#include "metrics_jsonl.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

namespace {

void expect(bool condition, const char *label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

std::string readFile(const std::filesystem::path &path) {
  std::ifstream input(path);
  std::ostringstream output;
  output << input.rdbuf();
  return output.str();
}

} // namespace

int main() {
  const std::filesystem::path path = std::filesystem::temp_directory_path() /
                                     "strok-metrics-jsonl-tests.jsonl";
  std::error_code error;
  std::filesystem::remove(path, error);
  {
    strok::MetricsJsonlWriter writer(path);
    expect(writer.write("{\"schema_version\":1}"), "metrics JSONL line writes");
  }
  expect(readFile(path) == "{\"schema_version\":1}\n",
         "metrics JSONL writer preserves one object per line");
  std::filesystem::remove(path, error);
}
