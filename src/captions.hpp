#pragma once

#include "frame.hpp"

#include <cstdint>
#include <string>

namespace contourtty {

std::string summariseFrameCaption(const Frame& frame);
std::string formatSrtTimestamp(int64_t pts_us);
std::string formatSrtCue(int index, int64_t start_us, int64_t end_us, const std::string& text);

}  // namespace contourtty
