#include <strok/graphics_emitter.hpp>

#include <cstdlib>

int main() {
  strok::CellBuffer cells(1, 1);
  cells.at(0, 0) = strok::Cell{
    .glyph = U'█',
    .fg = strok::Rgb{.r = 255, .g = 0, .b = 0},
  };

  strok::GraphicsFrameState state;
  const strok::GraphicsFrameOptions options{
    .protocol = strok::GraphicsProtocol::Kitty,
    .image_id = 1,
    .placement_id = 1,
  };
  const strok::GraphicsFrameResult first = strok::emitGraphicsFrame(cells, options, &state);
  if (first.bytes.empty() || first.raster_bytes == 0) {
    return EXIT_FAILURE;
  }
  const strok::GraphicsFrameResult second = strok::emitGraphicsFrame(cells, options, &state);
  if (!second.bytes.empty() || second.raster_bytes != first.raster_bytes) {
    return EXIT_FAILURE;
  }
  return EXIT_SUCCESS;
}
