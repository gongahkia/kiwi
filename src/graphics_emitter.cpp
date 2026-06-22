#include "graphics_emitter.hpp"

#include "graphics_alignment.hpp"
#include "iterm_inline.hpp"
#include "kitty_graphics.hpp"
#include "raster_compose.hpp"

#include <algorithm>
#include <cstddef>
#include <optional>
#include <stdexcept>
#include <utility>
#include <vector>

namespace contourtty {
namespace {

struct RasterDirtyRect {
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
};

bool sameRasterLayout(const RasterImage& lhs, const RasterImage& rhs) {
  return lhs.width == rhs.width && lhs.height == rhs.height && lhs.rgb.size() == rhs.rgb.size();
}

std::optional<RasterDirtyRect> dirtyRect(const RasterImage& previous, const RasterImage& current) {
  if (!sameRasterLayout(previous, current)) {
    return RasterDirtyRect{.x = 0, .y = 0, .width = current.width, .height = current.height};
  }
  int min_x = current.width;
  int min_y = current.height;
  int max_x = -1;
  int max_y = -1;
  for (int y = 0; y < current.height; ++y) {
    for (int x = 0; x < current.width; ++x) {
      const std::size_t index = (static_cast<std::size_t>(y) * static_cast<std::size_t>(current.width) + static_cast<std::size_t>(x)) * 3U;
      if (previous.rgb[index] == current.rgb[index] &&
          previous.rgb[index + 1U] == current.rgb[index + 1U] &&
          previous.rgb[index + 2U] == current.rgb[index + 2U]) {
        continue;
      }
      min_x = std::min(min_x, x);
      min_y = std::min(min_y, y);
      max_x = std::max(max_x, x);
      max_y = std::max(max_y, y);
    }
  }
  if (max_x < min_x || max_y < min_y) {
    return std::nullopt;
  }
  return RasterDirtyRect{.x = min_x, .y = min_y, .width = max_x - min_x + 1, .height = max_y - min_y + 1};
}

std::vector<uint8_t> cropRasterRgb(const RasterImage& image, RasterDirtyRect rect) {
  std::vector<uint8_t> cropped;
  cropped.reserve(static_cast<std::size_t>(rect.width) * static_cast<std::size_t>(rect.height) * 3U);
  for (int y = 0; y < rect.height; ++y) {
    const std::size_t row = static_cast<std::size_t>(rect.y + y) * static_cast<std::size_t>(image.width) + static_cast<std::size_t>(rect.x);
    const std::size_t begin = row * 3U;
    const std::size_t end = begin + static_cast<std::size_t>(rect.width) * 3U;
    cropped.insert(cropped.end(), image.rgb.begin() + static_cast<std::ptrdiff_t>(begin), image.rgb.begin() + static_cast<std::ptrdiff_t>(end));
  }
  return cropped;
}

bool stateMatches(const GraphicsFrameState& state, const GraphicsFrameOptions& options, const CellBuffer& cells, const RasterImage& raster) {
  return state.previous_raster.has_value() &&
         state.protocol == options.protocol &&
         state.image_id == options.image_id &&
         state.placement_id == options.placement_id &&
         state.columns == cells.cols() &&
         state.rows == cells.rows() &&
         sameRasterLayout(*state.previous_raster, raster);
}

void rememberFrame(GraphicsFrameState* state, const GraphicsFrameOptions& options, const CellBuffer& cells, RasterImage raster) {
  if (state == nullptr) {
    return;
  }
  state->protocol = options.protocol;
  state->image_id = options.image_id;
  state->placement_id = options.placement_id;
  state->columns = cells.cols();
  state->rows = cells.rows();
  state->previous_raster = std::move(raster);
}

GraphicsFrameResult emitFullGraphicsFrame(const CellBuffer& cells, const GraphicsFrameOptions& options, const RasterImage& raster) {
  switch (options.protocol) {
    case GraphicsProtocol::Kitty:
      return GraphicsFrameResult{
        .bytes = encodeKittyRgb24(raster, KittyImageOptions{
          .image_id = options.image_id,
          .placement_id = options.placement_id,
          .columns = cells.cols(),
          .rows = cells.rows(),
        }),
        .raster_bytes = raster.rgb.size(),
      };
    case GraphicsProtocol::ITermInline:
      return GraphicsFrameResult{
        .bytes = encodeITermInlineRgb24(raster, ITermInlineOptions{
          .width = std::to_string(cells.cols()),
          .height = std::to_string(cells.rows()),
        }),
        .raster_bytes = raster.rgb.size(),
      };
    case GraphicsProtocol::Sixel:
    case GraphicsProtocol::None:
      throw std::runtime_error("graphics protocol is not implemented");
  }
  throw std::runtime_error("graphics protocol is not implemented");
}

}  // namespace

GraphicsFrameResult emitGraphicsFrame(const CellBuffer& cells, const GraphicsFrameOptions& options) {
  return emitGraphicsFrame(cells, options, nullptr);
}

GraphicsFrameResult emitGraphicsFrame(const CellBuffer& cells, const GraphicsFrameOptions& options, GraphicsFrameState* state) {
  RasterImage raster = rasterComposeCells(cells, options.color_mode, options.dither_mode, options.glyph_font);
  (void)graphicsAlignmentForRaster(cells.cols(), cells.rows(), raster.width, raster.height);

  if (state != nullptr && options.protocol == GraphicsProtocol::Kitty && stateMatches(*state, options, cells, raster)) {
    const std::optional<RasterDirtyRect> rect = dirtyRect(*state->previous_raster, raster);
    if (!rect.has_value()) {
      rememberFrame(state, options, cells, std::move(raster));
      return GraphicsFrameResult{.raster_bytes = state->previous_raster->rgb.size()};
    }
    const std::vector<uint8_t> cropped = cropRasterRgb(raster, *rect);
    std::string bytes = encodeKittyAnimationFrameRgb24(cropped, KittyAnimationFrameOptions{
                                                                   .image_id = options.image_id,
                                                                   .frame_number = 1,
                                                                   .x = rect->x,
                                                                   .y = rect->y,
                                                                   .width = rect->width,
                                                                   .height = rect->height,
                                                                 });
    bytes += controlKittyAnimationFrame(options.image_id, 1);
    const std::size_t raster_bytes = raster.rgb.size();
    rememberFrame(state, options, cells, std::move(raster));
    return GraphicsFrameResult{.bytes = std::move(bytes), .raster_bytes = raster_bytes};
  }

  const GraphicsFrameResult frame = emitFullGraphicsFrame(cells, options, raster);
  rememberFrame(state, options, cells, std::move(raster));
  return frame;
}

}  // namespace contourtty
