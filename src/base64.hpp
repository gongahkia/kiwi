#pragma once

#include <cstdint>
#include <span>
#include <string>

namespace contourtty {

std::string base64Encode(std::span<const uint8_t> bytes);

}  // namespace contourtty
