#include <strok/c_api.h>

#include <string.h>

int main(void) {
  StrokRendererConfig config;
  StrokRenderGrid grid;
  StrokRenderer* renderer = 0;
  strok_renderer_config_init(&config);
  strok_render_grid_init(&grid);
  grid.cols = 2;
  grid.rows = 2;

  if (strok_renderer_create(&config, &grid, &renderer) != STROK_STATUS_SUCCESS || renderer == 0) {
    return 1;
  }
  if (strok_renderer_reset(renderer) != STROK_STATUS_SUCCESS) {
    strok_renderer_destroy(renderer);
    return 1;
  }
  strok_renderer_destroy(renderer);

  renderer = 0;
  config.cell_aspect = 0.0;
  if (strok_renderer_create(&config, &grid, &renderer) != STROK_STATUS_INVALID_ARGUMENT || renderer != 0) {
    return 1;
  }
  if (strlen(strok_last_error_message()) == 0U) {
    return 1;
  }
  strok_renderer_destroy(renderer);
  if (strok_renderer_reset(0) != STROK_STATUS_INVALID_ARGUMENT || strlen(strok_last_error_message()) == 0U) {
    return 1;
  }
  strok_renderer_destroy(0);
  return 0;
}
