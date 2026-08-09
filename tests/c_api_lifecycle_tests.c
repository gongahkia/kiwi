#include <strok/c_api.h>

#include <stdint.h>
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
  {
    const uint8_t rgb[12] = {
      0, 0, 0, 255, 255, 255,
      255, 0, 0, 0, 0, 255,
    };
    const uint8_t rgba[16] = {
      0, 0, 0, 1, 255, 255, 255, 2,
      255, 0, 0, 3, 0, 0, 255, 4,
    };
    const uint8_t bgra[16] = {
      0, 0, 0, 1, 255, 255, 255, 2,
      0, 0, 255, 3, 255, 0, 0, 4,
    };
    const uint8_t padded_rgba[24] = {
      0, 0, 0, 1, 255, 255, 255, 2, 9, 8, 7, 6,
      255, 0, 0, 3, 0, 0, 255, 4, 5, 4, 3, 2,
    };
    StrokColorImageView image;
    strok_color_image_view_init(&image);
    if (image.version != STROK_C_ABI_VERSION || image.struct_size != sizeof(image)) {
      strok_renderer_destroy(renderer);
      return 1;
    }
    image.data = rgb;
    image.width = 2;
    image.height = 2;
    image.row_stride_bytes = 6;
    image.pixel_format = STROK_COLOR_PIXEL_FORMAT_RGB24;
    if (strok_renderer_render_color(renderer, &image) != STROK_STATUS_SUCCESS) {
      strok_renderer_destroy(renderer);
      return 1;
    }
    image.data = rgba;
    image.row_stride_bytes = 8;
    image.pixel_format = STROK_COLOR_PIXEL_FORMAT_RGBA8;
    if (strok_renderer_render_color(renderer, &image) != STROK_STATUS_SUCCESS) {
      strok_renderer_destroy(renderer);
      return 1;
    }
    image.data = bgra;
    image.pixel_format = STROK_COLOR_PIXEL_FORMAT_BGRA8;
    if (strok_renderer_render_color(renderer, &image) != STROK_STATUS_SUCCESS) {
      strok_renderer_destroy(renderer);
      return 1;
    }
    image.data = padded_rgba;
    image.row_stride_bytes = 12;
    image.pixel_format = STROK_COLOR_PIXEL_FORMAT_RGBA8;
    if (strok_renderer_render_color(renderer, &image) != STROK_STATUS_SUCCESS) {
      strok_renderer_destroy(renderer);
      return 1;
    }
    image.data = 0;
    if (strok_renderer_render_color(renderer, &image) != STROK_STATUS_INVALID_ARGUMENT || strlen(strok_last_error_message()) == 0U) {
      strok_renderer_destroy(renderer);
      return 1;
    }
    image.data = rgb;
    image.row_stride_bytes = 5;
    image.pixel_format = STROK_COLOR_PIXEL_FORMAT_RGB24;
    if (strok_renderer_render_color(renderer, &image) != STROK_STATUS_INVALID_ARGUMENT || strlen(strok_last_error_message()) == 0U) {
      strok_renderer_destroy(renderer);
      return 1;
    }
    image.row_stride_bytes = 6;
    image.pixel_format = UINT32_C(99);
    if (strok_renderer_render_color(renderer, &image) != STROK_STATUS_INVALID_ARGUMENT || strlen(strok_last_error_message()) == 0U) {
      strok_renderer_destroy(renderer);
      return 1;
    }
    image.pixel_format = STROK_COLOR_PIXEL_FORMAT_RGB24;
    if (strok_renderer_render_color(renderer, &image) != STROK_STATUS_SUCCESS) {
      strok_renderer_destroy(renderer);
      return 1;
    }
    {
      const double depth_values[4] = {1.0, 2.0, 3.0, 4.0};
      const double normal_values[12] = {0.0, 0.0, 1.0, 0.0, 0.0, 1.0,
                                        0.0, 0.0, 1.0, 0.0, 0.0, 1.0};
      StrokDepthImageView depth;
      StrokNormalImageView normals;
      StrokRenderInput input;
      strok_depth_image_view_init(&depth);
      strok_normal_image_view_init(&normals);
      strok_render_input_init(&input);
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
        strok_renderer_destroy(renderer);
        return 1;
      }
      input.depth = 0;
      input.normals = 0;
      if (strok_renderer_render_input(renderer, &input) != STROK_STATUS_SUCCESS) {
        strok_renderer_destroy(renderer);
        return 1;
      }
      depth.width = 1;
      input.depth = &depth;
      if (strok_renderer_render_input(renderer, &input) != STROK_STATUS_INVALID_ARGUMENT || strlen(strok_last_error_message()) == 0U) {
        strok_renderer_destroy(renderer);
        return 1;
      }
      depth.width = 2;
      input.normals = &normals;
      normals.row_stride_bytes = 5U * sizeof(double);
      if (strok_renderer_render_input(renderer, &input) != STROK_STATUS_INVALID_ARGUMENT || strlen(strok_last_error_message()) == 0U) {
        strok_renderer_destroy(renderer);
        return 1;
      }
    }
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
