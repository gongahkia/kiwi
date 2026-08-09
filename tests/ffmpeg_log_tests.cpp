#include "ffmpeg_log.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

extern "C" {
#include <libavutil/log.h>
}

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
  const std::filesystem::path path =
      std::filesystem::temp_directory_path() / "strok-ffmpeg-log-tests.log";
  std::error_code error;
  std::filesystem::remove(path, error);
  {
    strok::Logger logger(path);
    strok::FfmpegLogScope scope("warning", logger);
    av_log(nullptr, AV_LOG_INFO, "ignore info diagnostic\n");
    av_log(nullptr, AV_LOG_WARNING, "forward warning diagnostic\n");
  }
  const std::string output = readFile(path);
  expect(
      output.find("ffmpeg level=warning message=forward warning diagnostic") !=
          std::string::npos,
      "warning FFmpeg diagnostics are routed to the logger");
  expect(output.find("ignore info diagnostic") == std::string::npos,
         "FFmpeg diagnostics respect the requested level");
  std::filesystem::remove(path, error);
}
