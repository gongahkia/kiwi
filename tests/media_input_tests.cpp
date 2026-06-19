#include "media_input.hpp"

#include <cstdlib>
#include <iostream>

namespace {

void expect(bool condition, const char* label) {
  if (!condition) {
    std::cerr << label << '\n';
    std::exit(1);
  }
}

}  // namespace

int main() {
  expect(!contourtty::isCameraInput("movie.mp4"), "file is not camera input");
  expect(contourtty::cameraInputSpec("avfoundation:1")->format == "avfoundation", "avfoundation alias");
  expect(contourtty::cameraInputSpec("avfoundation:1")->device == "1", "avfoundation device");
  expect(contourtty::cameraInputSpec("v4l2:/dev/video2")->format == "v4l2", "v4l2 alias");
  expect(contourtty::cameraInputSpec("/dev/video0")->device == "/dev/video0", "linux device path");
  expect(contourtty::cameraInputSpec("dshow:video=Integrated Camera")->format == "dshow", "dshow alias");
#if defined(__APPLE__)
  expect(contourtty::cameraInputSpec("cam")->format == "avfoundation", "mac cam format");
#elif defined(__linux__)
  expect(contourtty::cameraInputSpec("cam")->format == "v4l2", "linux cam format");
#elif defined(_WIN32)
  expect(contourtty::cameraInputSpec("cam")->format == "dshow", "windows cam format");
#endif
}
