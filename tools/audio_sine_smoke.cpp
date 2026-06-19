#include "audio_backend.hpp"

#include <cstdlib>
#include <exception>
#include <iostream>
#include <stdexcept>

namespace {

double parseSeconds(int argc, char** argv) {
  if (argc <= 1) {
    return 0.5;
  }
  char* end = nullptr;
  const double parsed = std::strtod(argv[1], &end);
  if (end == argv[1] || *end != '\0' || parsed <= 0.0) {
    throw std::runtime_error("usage: audio_sine_smoke [seconds]");
  }
  return parsed;
}

}  // namespace

int main(int argc, char** argv) {
  try {
    contourtty::SineSmokeOptions options;
    options.seconds = parseSeconds(argc, argv);
    const auto result = contourtty::playSineSmoke(options);
    std::cout << "played sine: frames=" << result.frames_generated
              << " sample_rate=" << result.sample_rate
              << " channels=" << result.channels << '\n';
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "fatal: " << error.what() << '\n';
    return 1;
  }
}
