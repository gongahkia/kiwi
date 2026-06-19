#include "stream_resolver.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

std::filesystem::path fakeYtDlp() {
  const auto path = std::filesystem::temp_directory_path() / ("contourtty-fake-ytdlp-" + std::to_string(getpid()));
  {
    std::ofstream out(path);
    out << "#!/bin/sh\n"
        << "for arg in \"$@\"; do\n"
        << "  [ \"$arg\" = best ] && exit 64\n"
        << "done\n"
        << "echo https://cdn.example.test/media.m3u8\n";
  }
  chmod(path.c_str(), 0700);
  return path;
}

}  // namespace

int main() {
  expect(!contourtty::isUrlInput("local.mp4"), "local input is not url");
  expect(contourtty::isUrlInput("https://example.test/live.m3u8"), "remote input is url");
  expect(!contourtty::requiresYtDlp("https://example.test/live.m3u8"), "direct hls skips yt-dlp");
  expect(contourtty::requiresYtDlp("https://www.youtube.com/watch?v=test"), "youtube uses yt-dlp");
  expect(contourtty::resolveMediaInput("https://example.test/live.m3u8") == "https://example.test/live.m3u8", "direct url preserved");

  const auto fake = fakeYtDlp();
  setenv("CONTOURTTY_YTDLP", fake.c_str(), 1);
  expect(contourtty::resolveMediaInput("https://youtu.be/test") == "https://cdn.example.test/media.m3u8", "youtube resolves through yt-dlp");

  setenv("CONTOURTTY_YTDLP", "/tmp/contourtty-no-such-ytdlp", 1);
  bool threw = false;
  try {
    (void)contourtty::resolveMediaInput("https://www.youtube.com/watch?v=test");
  } catch (const std::runtime_error&) {
    threw = true;
  }
  expect(threw, "missing yt-dlp reports error");
  unsetenv("CONTOURTTY_YTDLP");
  std::filesystem::remove(fake);
}
