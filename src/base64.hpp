#pragma once

#include <cstdint>
#include <span>
#include <string>

namespace strok {

std::string base64Encode(std::span<const uint8_t> bytes);

}  // namespace strok
