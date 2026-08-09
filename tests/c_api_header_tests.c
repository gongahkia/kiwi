#include <strok/c_api.h>

int main(void) {
  const uint32_t version = STROK_C_ABI_VERSION;
  StrokRendererConfig config;
  StrokRenderGrid grid;
  StrokColorImageView image;
  StrokDepthImageView depth;
  StrokNormalImageView normal;
  StrokRenderInput input;
  StrokCell cell;
  strok_renderer_config_init(&config);
  strok_render_grid_init(&grid);
  strok_color_image_view_init(&image);
  strok_depth_image_view_init(&depth);
  strok_normal_image_view_init(&normal);
  strok_render_input_init(&input);
  return version == UINT32_C(0x00010003) &&
                 config.version == version &&
                 config.struct_size == sizeof(config) &&
                 config.mode == STROK_RENDERER_MODE_LUMINANCE &&
                 grid.version == version &&
                 grid.struct_size == sizeof(grid) &&
                 image.version == version &&
                 image.struct_size == sizeof(image) &&
                 image.pixel_format == STROK_COLOR_PIXEL_FORMAT_RGB24 &&
                 depth.version == version && depth.struct_size == sizeof(depth) &&
                 normal.version == version && normal.struct_size == sizeof(normal) &&
                 input.version == version && input.struct_size == sizeof(input) &&
                 sizeof(cell.glyph) == sizeof(uint32_t) && sizeof(cell.fg_r) == sizeof(uint8_t) &&
                 sizeof(cell.bg_b) == sizeof(uint8_t)
             ? 0
             : 1;
}
