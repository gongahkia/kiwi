#include <strok/c_api.h>

int main(void) {
  const uint32_t version = STROK_C_ABI_VERSION;
  StrokRendererConfig config;
  StrokRenderGrid grid;
  strok_renderer_config_init(&config);
  strok_render_grid_init(&grid);
  return version == UINT32_C(0x00010000) &&
                 config.version == version &&
                 config.struct_size == sizeof(config) &&
                 config.mode == STROK_RENDERER_MODE_LUMINANCE &&
                 grid.version == version &&
                 grid.struct_size == sizeof(grid)
             ? 0
             : 1;
}
