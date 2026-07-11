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
  expect(!strok::isCameraInput("movie.mp4"), "file is not camera input");
  expect(strok::cameraInputSpec("avfoundation:1")->format == "avfoundation", "avfoundation alias");
  expect(strok::cameraInputSpec("avfoundation:1")->device == "1", "avfoundation device");
  expect(strok::cameraInputSpec("v4l2:/dev/video2")->format == "v4l2", "v4l2 alias");
  expect(strok::cameraInputSpec("/dev/video0")->device == "/dev/video0", "linux device path");
  expect(strok::cameraInputSpec("dshow:video=Integrated Camera")->format == "dshow", "dshow alias");
#if defined(__APPLE__)
  expect(strok::cameraInputSpec("cam")->format == "avfoundation", "mac cam format");
#elif defined(__linux__)
  expect(strok::cameraInputSpec("cam")->format == "v4l2", "linux cam format");
#elif defined(_WIN32)
  expect(strok::cameraInputSpec("cam")->format == "dshow", "windows cam format");
#endif
}
