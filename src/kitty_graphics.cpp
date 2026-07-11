#include "kitty_graphics.hpp"

#include "base64.hpp"

#include <algorithm>
#include <limits>
#include <stdexcept>

namespace strok {
namespace {

constexpr char kEsc[] = "\x1b_G";
constexpr char kSt[] = "\x1b\\";

std::size_t checkedRgbByteCount(int width, int height) {
  if (width <= 0 || height <= 0) {
    throw std::invalid_argument("kitty image dimensions must be positive");
  }
  const std::size_t w = static_cast<std::size_t>(width);
  const std::size_t h = static_cast<std::size_t>(height);
  if (w > std::numeric_limits<std::size_t>::max() / h / 3U) {
    throw std::invalid_argument("kitty image dimensions overflow");
  }
  return w * h * 3U;
}

void validateOptions(const KittyImageOptions& options) {
  if (options.image_id == 0) {
    throw std::invalid_argument("kitty image id must be non-zero");
  }
  if (options.placement_id == 0) {
    throw std::invalid_argument("kitty placement id must be non-zero");
  }
  if (options.columns < 0 || options.rows < 0) {
    throw std::invalid_argument("kitty placement dimensions cannot be negative");
  }
  if (options.chunk_size == 0 || options.chunk_size > 4096 || options.chunk_size % 4U != 0U) {
    throw std::invalid_argument("kitty chunk size must be a positive multiple of 4 no larger than 4096");
  }
}

void validateAnimationFrameOptions(const KittyAnimationFrameOptions& options) {
  if (options.image_id == 0) {
    throw std::invalid_argument("kitty image id must be non-zero");
  }
  if (options.frame_number == 0) {
    throw std::invalid_argument("kitty frame number must be non-zero");
  }
  if (options.x < 0 || options.y < 0 || options.width <= 0 || options.height <= 0) {
    throw std::invalid_argument("kitty animation frame rectangle must be positive");
  }
  if (options.chunk_size == 0 || options.chunk_size > 4096 || options.chunk_size % 4U != 0U) {
    throw std::invalid_argument("kitty chunk size must be a positive multiple of 4 no larger than 4096");
  }
}

void appendChunk(std::string& output, const std::string& control, std::string_view payload) {
  output.append(kEsc);
  output.append(control);
  output.push_back(';');
  output.append(payload);
  output.append(kSt);
}

std::string makeFirstChunkControl(int width, int height, const KittyImageOptions& options, bool more) {
  std::string control = "a=T,t=d,f=24,s=" + std::to_string(width) + ",v=" + std::to_string(height) +
                        ",i=" + std::to_string(options.image_id) + ",p=" + std::to_string(options.placement_id);
  if (options.suppress_response) {
    control += ",q=2";
  }
  if (options.columns > 0) {
    control += ",c=" + std::to_string(options.columns);
  }
  if (options.rows > 0) {
    control += ",r=" + std::to_string(options.rows);
  }
  if (options.leave_cursor) {
    control += ",C=1";
  }
  control += more ? ",m=1" : ",m=0";
  return control;
}

std::string makeAnimationFrameControl(const KittyAnimationFrameOptions& options, bool more) {
  std::string control = "a=f,t=d,f=24,i=" + std::to_string(options.image_id) +
                        ",r=" + std::to_string(options.frame_number) +
                        ",x=" + std::to_string(options.x) +
                        ",y=" + std::to_string(options.y) +
                        ",s=" + std::to_string(options.width) +
                        ",v=" + std::to_string(options.height);
  if (options.replace) {
    control += ",X=1";
  }
  if (options.suppress_response) {
    control += ",q=2";
  }
  control += more ? ",m=1" : ",m=0";
  return control;
}

std::string makeAnimationFollowupChunkControl(bool suppress_response, bool more) {
  std::string control = "a=f";
  if (suppress_response) {
    control += ",q=2";
  }
  control += more ? ",m=1" : ",m=0";
  return control;
}

std::string makeFollowupChunkControl(bool suppress_response, bool more) {
  std::string control;
  if (suppress_response) {
    control = "q=2,";
  }
  control += more ? "m=1" : "m=0";
  return control;
}

}  // namespace

std::string encodeKittyRgb24(std::span<const uint8_t> rgb, int width, int height, const KittyImageOptions& options) {
  const std::size_t expected = checkedRgbByteCount(width, height);
  if (rgb.size() != expected) {
    throw std::invalid_argument("kitty RGB24 payload size does not match dimensions");
  }
  validateOptions(options);

  const std::string payload = base64Encode(rgb);
  std::string output;
  output.reserve(payload.size() + (payload.size() / options.chunk_size + 1U) * 64U);
  for (std::size_t offset = 0; offset < payload.size();) {
    const std::size_t chunk_size = std::min(options.chunk_size, payload.size() - offset);
    const bool first = offset == 0;
    const bool more = offset + chunk_size < payload.size();
    const std::string control = first ? makeFirstChunkControl(width, height, options, more) : makeFollowupChunkControl(options.suppress_response, more);
    appendChunk(output, control, std::string_view(payload).substr(offset, chunk_size));
    offset += chunk_size;
  }
  return output;
}

std::string encodeKittyRgb24(const RasterImage& image, const KittyImageOptions& options) {
  return encodeKittyRgb24(image.rgb, image.width, image.height, options);
}

std::string encodeKittyAnimationFrameRgb24(std::span<const uint8_t> rgb, const KittyAnimationFrameOptions& options) {
  const std::size_t expected = checkedRgbByteCount(options.width, options.height);
  if (rgb.size() != expected) {
    throw std::invalid_argument("kitty animation RGB24 payload size does not match dimensions");
  }
  validateAnimationFrameOptions(options);

  const std::string payload = base64Encode(rgb);
  std::string output;
  output.reserve(payload.size() + (payload.size() / options.chunk_size + 1U) * 64U);
  for (std::size_t offset = 0; offset < payload.size();) {
    const std::size_t chunk_size = std::min(options.chunk_size, payload.size() - offset);
    const bool first = offset == 0;
    const bool more = offset + chunk_size < payload.size();
    const std::string control = first ? makeAnimationFrameControl(options, more) : makeAnimationFollowupChunkControl(options.suppress_response, more);
    appendChunk(output, control, std::string_view(payload).substr(offset, chunk_size));
    offset += chunk_size;
  }
  return output;
}

std::string controlKittyAnimationFrame(uint32_t image_id, uint32_t frame_number, bool suppress_response) {
  if (image_id == 0) {
    throw std::invalid_argument("kitty image id must be non-zero");
  }
  if (frame_number == 0) {
    throw std::invalid_argument("kitty frame number must be non-zero");
  }
  std::string control = "a=a,i=" + std::to_string(image_id) + ",c=" + std::to_string(frame_number);
  if (suppress_response) {
    control += ",q=2";
  }
  std::string output;
  appendChunk(output, control, "");
  return output;
}

std::string deleteKittyImage(uint32_t image_id, uint32_t placement_id, bool suppress_response) {
  if (image_id == 0) {
    throw std::invalid_argument("kitty image id must be non-zero");
  }
  std::string control = "a=d,d=i,i=" + std::to_string(image_id);
  if (placement_id != 0) {
    control += ",p=" + std::to_string(placement_id);
  }
  if (suppress_response) {
    control += ",q=2";
  }
  std::string output;
  appendChunk(output, control, "");
  return output;
}

}  // namespace strok
