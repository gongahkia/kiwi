#include "graphics_emitter.hpp"

#include "graphics_alignment.hpp"
#include "iterm_inline.hpp"
#include "kitty_graphics.hpp"
#include "raster_compose.hpp"

#include <stdexcept>

namespace contourtty {

GraphicsFrameResult emitGraphicsFrame(const CellBuffer& cells, const GraphicsFrameOptions& options) {
  const RasterImage raster = rasterComposeCells(cells, options.color_mode, options.dither_mode, options.glyph_font);
  (void)graphicsAlignmentForRaster(cells.cols(), cells.rows(), raster.width, raster.height);

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

}  // namespace contourtty
