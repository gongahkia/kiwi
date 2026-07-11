#include "base64.hpp"

namespace strok {

std::string base64Encode(std::span<const uint8_t> bytes) {
  constexpr char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string encoded;
  encoded.reserve(((bytes.size() + 2U) / 3U) * 4U);
  for (std::size_t index = 0; index < bytes.size(); index += 3U) {
    const uint32_t a = bytes[index];
    const uint32_t b = (index + 1U < bytes.size()) ? bytes[index + 1U] : 0U;
    const uint32_t c = (index + 2U < bytes.size()) ? bytes[index + 2U] : 0U;
    const uint32_t triple = (a << 16U) | (b << 8U) | c;
    encoded.push_back(alphabet[(triple >> 18U) & 0x3FU]);
    encoded.push_back(alphabet[(triple >> 12U) & 0x3FU]);
    encoded.push_back(index + 1U < bytes.size() ? alphabet[(triple >> 6U) & 0x3FU] : '=');
    encoded.push_back(index + 2U < bytes.size() ? alphabet[triple & 0x3FU] : '=');
  }
  return encoded;
}

}  // namespace strok
