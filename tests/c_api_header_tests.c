#include <strok/c_api.h>

int main(void) {
  const uint32_t version = STROK_C_ABI_VERSION;
  StrokRendererConfig config;
  StrokRenderGrid grid;
  StrokColorImageView image;
  strok_renderer_config_init(&config);
  strok_render_grid_init(&grid);
  strok_color_image_view_init(&image);
  return version == UINT32_C(0x00010001) &&
                 config.version == version &&
                 config.struct_size == sizeof(config) &&
                 config.mode == STROK_RENDERER_MODE_LUMINANCE &&
                 grid.version == version &&
                 grid.struct_size == sizeof(grid) &&
                 image.version == version &&
                 image.struct_size == sizeof(image) &&
                 image.pixel_format == STROK_COLOR_PIXEL_FORMAT_RGB24
             ? 0
             : 1;
}
