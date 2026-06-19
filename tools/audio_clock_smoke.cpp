#include "audio_backend.hpp"
#include "audio_decode.hpp"

#include <chrono>
#include <cstdint>
#include <exception>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>

int main(int argc, char** argv) {
  try {
    if (argc != 2) {
      throw std::runtime_error("usage: audio_clock_smoke <media-file>");
    }
    const auto decoded = contourtty::decodeAudioFile(std::filesystem::path(argv[1]));
    contourtty::PcmPlayer player(
      decoded.samples,
      contourtty::PcmPlaybackOptions{
        .sample_rate = static_cast<uint32_t>(decoded.sample_rate),
        .channels = static_cast<uint32_t>(decoded.channels),
      });
    player.start();

    std::vector<int64_t> clocks;
    for (int i = 0; i < 4; ++i) {
      std::this_thread::sleep_for(std::chrono::milliseconds(80));
      clocks.push_back(player.masterClockUs());
    }
    const auto playback = player.waitUntilComplete();

    std::cout << "clock_us:";
    for (const int64_t clock : clocks) {
      std::cout << ' ' << clock;
    }
    std::cout << "\nplayed audio: frames=" << playback.frames_played
              << " trailing_silence_frames=" << playback.trailing_silence_frames << '\n';

    for (std::size_t i = 1; i < clocks.size(); ++i) {
      if (clocks[i] <= clocks[i - 1]) {
        return 1;
      }
    }
    return player.masterClockUs() > 0 ? 0 : 1;
  } catch (const std::exception& error) {
    std::cerr << "fatal: " << error.what() << '\n';
    return 1;
  }
}
