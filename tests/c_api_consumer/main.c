#include <strok/c_api.h>

#include <stdint.h>
#include <string.h>

static int failure(StrokRenderer* renderer) {
  strok_renderer_destroy(renderer);
  return 1;
}

int main(void) {
  const uint8_t rgb[12] = {
    0, 0, 0, 255, 255, 255,
    255, 0, 0, 0, 0, 255,
  };
  const double depth_values[4] = {1.0, 2.0, 3.0, 4.0};
  const double normal_values[12] = {0.0, 0.0, 1.0, 0.0, 0.0, 1.0,
                                    0.0, 0.0, 1.0, 0.0, 0.0, 1.0};
  StrokRendererConfig config;
  StrokRenderGrid grid;
  StrokColorImageView image;
  StrokDepthImageView depth;
  StrokNormalImageView normals;
  StrokRenderInput input;
  StrokRenderer* renderer = 0;
  int32_t cols = -1;
  int32_t rows = -1;
  StrokCell cell = {0};

  strok_renderer_config_init(&config);
  strok_render_grid_init(&grid);
  strok_color_image_view_init(&image);
  strok_depth_image_view_init(&depth);
  strok_normal_image_view_init(&normals);
  strok_render_input_init(&input);
  grid.cols = 2;
  grid.rows = 2;
  if (strok_renderer_create(&config, &grid, &renderer) != STROK_STATUS_SUCCESS || renderer == 0) {
    return failure(renderer);
  }

  if (strok_renderer_cell_buffer_dimensions(renderer, &cols, &rows) != STROK_STATUS_INVALID_ARGUMENT ||
      cols != -1 || rows != -1 || strlen(strok_last_error_message()) == 0U) {
    return failure(renderer);
  }

  image.data = rgb;
  image.width = 2;
  image.height = 2;
  image.row_stride_bytes = 6;
  if (strok_renderer_render_color(renderer, &image) != STROK_STATUS_SUCCESS ||
      strok_renderer_cell_buffer_dimensions(renderer, &cols, &rows) != STROK_STATUS_SUCCESS ||
      cols <= 0 || rows <= 0 ||
      strok_renderer_cell_buffer_at(renderer, 0, 0, &cell) != STROK_STATUS_SUCCESS ||
      cell.glyph > UINT32_C(0x10ffff)) {
    return failure(renderer);
  }
  if (strok_renderer_cell_buffer_at(renderer, cols, 0, &cell) != STROK_STATUS_INVALID_ARGUMENT ||
      strlen(strok_last_error_message()) == 0U) {
    return failure(renderer);
  }

  depth.data = depth_values;
  depth.width = 2;
  depth.height = 2;
  depth.row_stride_bytes = 2U * sizeof(double);
  normals.data = normal_values;
  normals.width = 2;
  normals.height = 2;
  normals.row_stride_bytes = 6U * sizeof(double);
  input.color = &image;
  input.depth = &depth;
  input.normals = &normals;
  if (strok_renderer_render_input(renderer, &input) != STROK_STATUS_SUCCESS) {
    return failure(renderer);
  }

  normals.row_stride_bytes = 5U * sizeof(double);
  if (strok_renderer_render_input(renderer, &input) != STROK_STATUS_INVALID_ARGUMENT ||
      strlen(strok_last_error_message()) == 0U ||
      strok_renderer_cell_buffer_at(renderer, 0, 0, &cell) != STROK_STATUS_SUCCESS) {
    return failure(renderer);
  }
  normals.row_stride_bytes = 6U * sizeof(double);
  image.data = 0;
  if (strok_renderer_render_color(renderer, &image) != STROK_STATUS_INVALID_ARGUMENT ||
      strlen(strok_last_error_message()) == 0U ||
      strok_renderer_reset(renderer) != STROK_STATUS_SUCCESS ||
      strok_renderer_cell_buffer_dimensions(renderer, &cols, &rows) != STROK_STATUS_SUCCESS) {
    return failure(renderer);
  }
  strok_renderer_destroy(renderer);

  renderer = 0;
  config.cell_aspect = 0.0;
  if (strok_renderer_create(&config, &grid, &renderer) != STROK_STATUS_INVALID_ARGUMENT || renderer != 0 ||
      strlen(strok_last_error_message()) == 0U) {
    return failure(renderer);
  }
  strok_renderer_destroy(0);
  return 0;
}
