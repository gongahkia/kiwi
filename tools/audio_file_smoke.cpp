#include "audio_backend.hpp"
#include "audio_decode.hpp"

#include <cstddef>
#include <exception>
#include <filesystem>
#include <iostream>
#include <stdexcept>

int main(int argc, char** argv) {
  try {
    if (argc != 2) {
      throw std::runtime_error("usage: audio_file_smoke <media-file>");
    }
    const auto decoded = contourtty::decodeAudioFile(std::filesystem::path(argv[1]));
    std::cout << "decoded audio: frames=" << (decoded.samples.size() / static_cast<std::size_t>(decoded.channels))
              << " decoded_frames=" << decoded.decoded_frames
              << " sample_rate=" << decoded.sample_rate
              << " channels=" << decoded.channels
              << " duration_us=" << decoded.duration_us << '\n';
    const auto playback = contourtty::playPcm(
      decoded.samples,
      contourtty::PcmPlaybackOptions{
        .sample_rate = static_cast<uint32_t>(decoded.sample_rate),
        .channels = static_cast<uint32_t>(decoded.channels),
      });
    const auto expected_frames = decoded.samples.size() / static_cast<std::size_t>(decoded.channels);
    std::cout << "played audio: frames=" << playback.frames_played
              << " trailing_silence_frames=" << playback.trailing_silence_frames << '\n';
    return playback.frames_played >= expected_frames ? 0 : 1;
  } catch (const std::exception& error) {
    std::cerr << "fatal: " << error.what() << '\n';
    return 1;
  }
}
