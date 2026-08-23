#include "gtk_gl_renderer.h"

#include <epoxy/gl.h>

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

enum {
  KIWI_GTK_GL_MAX_CELLS = 256 * 1024,
  KIWI_GTK_GL_MAX_CELL_UPDATES = 4096,
  KIWI_GTK_GL_MAX_GLYPHS = 512 * 1024,
  KIWI_GTK_GL_MAX_ATLAS_BYTES = 4 * 1024 * 1024,
};

typedef struct KiwiGtkGlSnapshot {
  KiwiGlyphInstance *cells;
  uint8_t *cell_dirty;
  uint32_t cell_count;
  int cells_dirty;
  int cells_full_upload;
  KiwiTextGlyphInstance *glyphs;
  uint32_t glyph_count;
  int glyphs_dirty;
  uint8_t *atlas_pixels;
  uint32_t atlas_bytes;
  uint32_t atlas_width;
  uint32_t atlas_height;
  uint64_t atlas_generation;
  KiwiFrameUniform frame;
  uint64_t revision;
} KiwiGtkGlSnapshot;

struct KiwiGtkGlRenderer {
  GtkGLArea *area;
  KiwiGtkGlSnapshot pending;
  char error[512];
  GLuint cell_buffer;
  GLuint glyph_buffer;
  GLuint atlas_texture;
  GLuint glyph_program;
  GLuint glyph_vertex_array;
  GLuint overlay_program;
  GLuint overlay_vertex_array;
  GLuint cursor_program;
  GLuint cursor_vertex_array;
  GLuint command_region_program;
  GLuint program;
  GLuint vertex_array;
  uint32_t cell_buffer_count;
  uint32_t glyph_buffer_count;
  uint64_t cell_full_uploads;
  uint64_t cell_subrange_uploads;
  uint64_t cell_subrange_bytes;
  uint64_t glyph_uploads;
  uint64_t glyph_upload_bytes;
  uint64_t uploaded_atlas_generation;
  uint32_t uploaded_atlas_width;
  uint32_t uploaded_atlas_height;
  int atlas_uploaded;
  uint64_t rendered_revision;
  gulong realize_handler;
  gulong render_handler;
  gulong unrealize_handler;
};

static const char kiwi_gtk_gl_vertex_source[] =
    "#version 330 core\n"
    "layout(location = 0) in vec2 position;\n"
    "layout(location = 1) in uint background;\n"
    "uniform vec2 grid;\n"
    "out vec4 background_color;\n"
    "vec2 corner(uint index) {\n"
    "  const vec2 corners[6] = vec2[6](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(1.0, 1.0));\n"
    "  return corners[index];\n"
    "}\n"
    "vec4 unpack_rgba(uint value) {\n"
    "  return vec4(float((value >> 16u) & 255u), float((value >> 8u) & 255u), float(value & 255u), float((value >> 24u) & 255u)) / 255.0;\n"
    "}\n"
    "void main() {\n"
    "  vec2 local = corner(uint(gl_VertexID));\n"
    "  vec2 point = (position + local) / grid;\n"
    "  gl_Position = vec4(point.x * 2.0 - 1.0, 1.0 - point.y * 2.0, 0.0, 1.0);\n"
    "  background_color = unpack_rgba(background);\n"
    "}\n";

static const char kiwi_gtk_gl_fragment_source[] =
    "#version 330 core\n"
    "in vec4 background_color;\n"
    "out vec4 color;\n"
    "void main() { color = background_color; }\n";

static const char kiwi_gtk_gl_glyph_vertex_source[] =
    "#version 330 core\n"
    "layout(location = 0) in vec2 position;\n"
    "layout(location = 1) in vec2 size;\n"
    "layout(location = 2) in vec2 uv_min;\n"
    "layout(location = 3) in vec2 uv_max;\n"
    "layout(location = 4) in uint foreground;\n"
    "layout(location = 5) in uint flags;\n"
    "layout(location = 6) in uint glyph;\n"
    "uniform vec2 grid;\n"
    "out vec2 atlas_uv;\n"
    "out vec2 local_position;\n"
    "out vec4 foreground_color;\n"
    "flat out uint glyph_flags;\n"
    "flat out uint glyph_id;\n"
    "vec2 corner(uint index) {\n"
    "  const vec2 corners[6] = vec2[6](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(1.0, 1.0));\n"
    "  return corners[index];\n"
    "}\n"
    "vec4 unpack_rgba(uint value) {\n"
    "  return vec4(float((value >> 16u) & 255u), float((value >> 8u) & 255u), float(value & 255u), float((value >> 24u) & 255u)) / 255.0;\n"
    "}\n"
    "void main() {\n"
    "  local_position = corner(uint(gl_VertexID));\n"
    "  vec2 point = (position + local_position * size) / grid;\n"
    "  gl_Position = vec4(point.x * 2.0 - 1.0, 1.0 - point.y * 2.0, 0.0, 1.0);\n"
    "  atlas_uv = uv_min + local_position * (uv_max - uv_min);\n"
    "  foreground_color = unpack_rgba(foreground);\n"
    "  glyph_flags = flags;\n"
    "  glyph_id = glyph;\n"
    "}\n";

static const char kiwi_gtk_gl_glyph_fragment_source[] =
    "#version 330 core\n"
    "in vec2 atlas_uv;\n"
    "in vec2 local_position;\n"
    "in vec4 foreground_color;\n"
    "flat in uint glyph_flags;\n"
    "flat in uint glyph_id;\n"
    "uniform sampler2D alpha_atlas;\n"
    "uniform vec4 hyperlink_color;\n"
    "out vec4 color;\n"
    "void main() {\n"
    "  if (glyph_id == 0u) discard;\n"
    "  vec4 value = foreground_color;\n"
    "  if ((glyph_flags & 1u) != 0u) value.rgb = min(vec3(1.0), value.rgb * 1.16);\n"
    "  if ((glyph_flags & 8u) != 0u) value.rgb *= 0.65;\n"
    "  if ((glyph_flags & 512u) != 0u && hyperlink_color.a > 0.0 && local_position.y > 0.91) { color = hyperlink_color; return; }\n"
    "  bool decoration = ((glyph_flags & 32u) != 0u && local_position.y > 0.88) || ((glyph_flags & 256u) != 0u && local_position.y > 0.46 && local_position.y < 0.54);\n"
    "  if (decoration) { color = value; return; }\n"
    "  float coverage = texture(alpha_atlas, atlas_uv).r;\n"
    "  if (coverage <= 0.0) discard;\n"
    "  color = vec4(value.rgb, value.a * coverage);\n"
    "}\n";

static const char kiwi_gtk_gl_overlay_vertex_source[] =
    "#version 330 core\n"
    "uniform vec2 grid;\n"
    "out vec2 cell_position;\n"
    "out vec2 local_position;\n"
    "vec2 corner(uint index) {\n"
    "  const vec2 corners[6] = vec2[6](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(1.0, 1.0));\n"
    "  return corners[index];\n"
    "}\n"
    "void main() {\n"
    "  float row = floor(float(gl_InstanceID) / grid.x);\n"
    "  float column = float(gl_InstanceID) - row * grid.x;\n"
    "  vec2 local = corner(uint(gl_VertexID));\n"
    "  vec2 point = (vec2(column, row) + local) / grid;\n"
    "  gl_Position = vec4(point.x * 2.0 - 1.0, 1.0 - point.y * 2.0, 0.0, 1.0);\n"
    "  cell_position = vec2(column, row);\n"
    "  local_position = local;\n"
    "}\n";

static const char kiwi_gtk_gl_overlay_fragment_source[] =
    "#version 330 core\n"
    "in vec2 cell_position;\n"
    "uniform vec4 range;\n"
    "uniform vec4 overlay_color;\n"
    "out vec4 color;\n"
    "void main() {\n"
    "  bool after_start = cell_position.y > range.y || (cell_position.y == range.y && cell_position.x >= range.x);\n"
    "  bool before_finish = cell_position.y < range.w || (cell_position.y == range.w && cell_position.x < range.z);\n"
    "  if (!after_start || !before_finish) discard;\n"
    "  color = overlay_color;\n"
    "}\n";

static const char kiwi_gtk_gl_command_region_fragment_source[] =
    "#version 330 core\n"
    "in vec2 cell_position;\n"
    "in vec2 local_position;\n"
    "uniform int boundary_count;\n"
    "uniform vec4 boundaries[32];\n"
    "uniform vec4 command_region_color;\n"
    "out vec4 color;\n"
    "void main() {\n"
    "  if (local_position.y > 0.04 || command_region_color.a <= 0.0) discard;\n"
    "  bool separator = false;\n"
    "  for (int index = 0; index < 32; index += 1) {\n"
    "    if (index >= boundary_count) break;\n"
    "    vec4 boundary = boundaries[index];\n"
    "    if (boundary.y == cell_position.y && (boundary.z == 2.0 || boundary.z == 3.0)) { separator = true; break; }\n"
    "  }\n"
    "  if (!separator) discard;\n"
    "  color = command_region_color;\n"
    "}\n";

static const char kiwi_gtk_gl_cursor_vertex_source[] =
    "#version 330 core\n"
    "uniform vec2 grid;\n"
    "uniform vec2 cursor_position;\n"
    "out vec2 local_position;\n"
    "vec2 corner(uint index) {\n"
    "  const vec2 corners[6] = vec2[6](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, 1.0), vec2(1.0, 0.0), vec2(1.0, 1.0));\n"
    "  return corners[index];\n"
    "}\n"
    "void main() {\n"
    "  local_position = corner(uint(gl_VertexID));\n"
    "  vec2 point = (cursor_position + local_position) / grid;\n"
    "  gl_Position = vec4(point.x * 2.0 - 1.0, 1.0 - point.y * 2.0, 0.0, 1.0);\n"
    "}\n";

static const char kiwi_gtk_gl_cursor_fragment_source[] =
    "#version 330 core\n"
    "in vec2 local_position;\n"
    "uniform vec4 cursor_color;\n"
    "uniform float cursor_visible;\n"
    "uniform float cursor_shape;\n"
    "uniform float cursor_blink;\n"
    "uniform float frame_time;\n"
    "out vec4 color;\n"
    "void main() {\n"
    "  if (cursor_visible < 0.5 || (cursor_blink > 0.5 && abs(sin(frame_time * 3.0)) < 0.15)) discard;\n"
    "  if (cursor_shape > 0.5 && cursor_shape < 1.5 && local_position.y < 0.82) discard;\n"
    "  if (cursor_shape > 1.5 && local_position.x > 0.18) discard;\n"
    "  color = cursor_color;\n"
    "}\n";

static void kiwi_gtk_gl_set_error(KiwiGtkGlRenderer *renderer, const char *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  vsnprintf(renderer->error, sizeof(renderer->error), format, arguments);
  va_end(arguments);
}

static void kiwi_gtk_gl_snapshot_clear(KiwiGtkGlSnapshot *snapshot) {
  g_free(snapshot->cells);
  g_free(snapshot->cell_dirty);
  g_free(snapshot->glyphs);
  g_free(snapshot->atlas_pixels);
  memset(snapshot, 0, sizeof(*snapshot));
}

static void *kiwi_gtk_gl_copy(const void *source, size_t bytes) {
  if (bytes == 0) return NULL;
  void *copy = g_malloc(bytes);
  if (copy != NULL) memcpy(copy, source, bytes);
  return copy;
}

static GLuint kiwi_gtk_gl_compile_shader(KiwiGtkGlRenderer *renderer, GLenum type,
                                         const char *source) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, NULL);
  glCompileShader(shader);
  GLint compiled = GL_FALSE;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
  if (compiled == GL_TRUE) return shader;
  char log[256] = {0};
  glGetShaderInfoLog(shader, sizeof(log), NULL, log);
  kiwi_gtk_gl_set_error(renderer, "GTK GL shader compilation failed: %s", log);
  glDeleteShader(shader);
  return 0;
}

static GLuint kiwi_gtk_gl_link_program(KiwiGtkGlRenderer *renderer,
                                       const char *vertex_source,
                                       const char *fragment_source) {
  GLuint vertex = kiwi_gtk_gl_compile_shader(renderer, GL_VERTEX_SHADER, vertex_source);
  if (vertex == 0) return 0;
  GLuint fragment = kiwi_gtk_gl_compile_shader(renderer, GL_FRAGMENT_SHADER, fragment_source);
  if (fragment == 0) {
    glDeleteShader(vertex);
    return 0;
  }
  GLuint program = glCreateProgram();
  glAttachShader(program, vertex);
  glAttachShader(program, fragment);
  glLinkProgram(program);
  glDeleteShader(vertex);
  glDeleteShader(fragment);
  GLint linked = GL_FALSE;
  glGetProgramiv(program, GL_LINK_STATUS, &linked);
  if (linked == GL_TRUE) return program;
  char log[256] = {0};
  glGetProgramInfoLog(program, sizeof(log), NULL, log);
  kiwi_gtk_gl_set_error(renderer, "GTK GL program link failed: %s", log);
  glDeleteProgram(program);
  return 0;
}

static int kiwi_gtk_gl_create_resources(KiwiGtkGlRenderer *renderer) {
  if (renderer->program != 0) return 1;
  renderer->program = kiwi_gtk_gl_link_program(renderer, kiwi_gtk_gl_vertex_source,
                                                kiwi_gtk_gl_fragment_source);
  if (renderer->program == 0) return 0;
  renderer->glyph_program = kiwi_gtk_gl_link_program(renderer,
                                                      kiwi_gtk_gl_glyph_vertex_source,
                                                      kiwi_gtk_gl_glyph_fragment_source);
  if (renderer->glyph_program == 0) {
    glDeleteProgram(renderer->program);
    renderer->program = 0;
    return 0;
  }
  renderer->overlay_program = kiwi_gtk_gl_link_program(renderer,
                                                        kiwi_gtk_gl_overlay_vertex_source,
                                                        kiwi_gtk_gl_overlay_fragment_source);
  if (renderer->overlay_program == 0) {
    glDeleteProgram(renderer->program);
    glDeleteProgram(renderer->glyph_program);
    renderer->program = 0;
    renderer->glyph_program = 0;
    return 0;
  }
  renderer->cursor_program = kiwi_gtk_gl_link_program(renderer,
                                                       kiwi_gtk_gl_cursor_vertex_source,
                                                       kiwi_gtk_gl_cursor_fragment_source);
  if (renderer->cursor_program == 0) {
    glDeleteProgram(renderer->program);
    glDeleteProgram(renderer->glyph_program);
    glDeleteProgram(renderer->overlay_program);
    renderer->program = 0;
    renderer->glyph_program = 0;
    renderer->overlay_program = 0;
    return 0;
  }
  renderer->command_region_program = kiwi_gtk_gl_link_program(renderer,
                                                               kiwi_gtk_gl_overlay_vertex_source,
                                                               kiwi_gtk_gl_command_region_fragment_source);
  if (renderer->command_region_program == 0) {
    glDeleteProgram(renderer->program);
    glDeleteProgram(renderer->glyph_program);
    glDeleteProgram(renderer->overlay_program);
    glDeleteProgram(renderer->cursor_program);
    renderer->program = 0;
    renderer->glyph_program = 0;
    renderer->overlay_program = 0;
    renderer->cursor_program = 0;
    return 0;
  }
  glGenVertexArrays(1, &renderer->vertex_array);
  glBindVertexArray(renderer->vertex_array);
  glGenBuffers(1, &renderer->cell_buffer);
  glBindBuffer(GL_ARRAY_BUFFER, renderer->cell_buffer);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(KiwiGlyphInstance),
                        (const void *)offsetof(KiwiGlyphInstance, x));
  glVertexAttribDivisor(0, 1);
  glEnableVertexAttribArray(1);
  glVertexAttribIPointer(1, 1, GL_UNSIGNED_INT, sizeof(KiwiGlyphInstance),
                         (const void *)offsetof(KiwiGlyphInstance, bg));
  glVertexAttribDivisor(1, 1);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);
  glGenVertexArrays(1, &renderer->glyph_vertex_array);
  glBindVertexArray(renderer->glyph_vertex_array);
  glGenBuffers(1, &renderer->glyph_buffer);
  glBindBuffer(GL_ARRAY_BUFFER, renderer->glyph_buffer);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, sizeof(KiwiTextGlyphInstance),
                        (const void *)offsetof(KiwiTextGlyphInstance, x));
  glVertexAttribDivisor(0, 1);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, sizeof(KiwiTextGlyphInstance),
                        (const void *)offsetof(KiwiTextGlyphInstance, width));
  glVertexAttribDivisor(1, 1);
  glEnableVertexAttribArray(2);
  glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, sizeof(KiwiTextGlyphInstance),
                        (const void *)offsetof(KiwiTextGlyphInstance, u0));
  glVertexAttribDivisor(2, 1);
  glEnableVertexAttribArray(3);
  glVertexAttribPointer(3, 2, GL_FLOAT, GL_FALSE, sizeof(KiwiTextGlyphInstance),
                        (const void *)offsetof(KiwiTextGlyphInstance, u1));
  glVertexAttribDivisor(3, 1);
  glEnableVertexAttribArray(4);
  glVertexAttribIPointer(4, 1, GL_UNSIGNED_INT, sizeof(KiwiTextGlyphInstance),
                         (const void *)offsetof(KiwiTextGlyphInstance, fg));
  glVertexAttribDivisor(4, 1);
  glEnableVertexAttribArray(5);
  glVertexAttribIPointer(5, 1, GL_UNSIGNED_INT, sizeof(KiwiTextGlyphInstance),
                         (const void *)offsetof(KiwiTextGlyphInstance, flags));
  glVertexAttribDivisor(5, 1);
  glEnableVertexAttribArray(6);
  glVertexAttribIPointer(6, 1, GL_UNSIGNED_INT, sizeof(KiwiTextGlyphInstance),
                         (const void *)offsetof(KiwiTextGlyphInstance, glyph));
  glVertexAttribDivisor(6, 1);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);
  glGenTextures(1, &renderer->atlas_texture);
  glBindTexture(GL_TEXTURE_2D, renderer->atlas_texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindTexture(GL_TEXTURE_2D, 0);
  glGenVertexArrays(1, &renderer->overlay_vertex_array);
  glGenVertexArrays(1, &renderer->cursor_vertex_array);
  return 1;
}

static void kiwi_gtk_gl_destroy_resources(KiwiGtkGlRenderer *renderer) {
  if (renderer->cell_buffer != 0) glDeleteBuffers(1, &renderer->cell_buffer);
  if (renderer->glyph_buffer != 0) glDeleteBuffers(1, &renderer->glyph_buffer);
  if (renderer->atlas_texture != 0) glDeleteTextures(1, &renderer->atlas_texture);
  if (renderer->vertex_array != 0) glDeleteVertexArrays(1, &renderer->vertex_array);
  if (renderer->glyph_vertex_array != 0) glDeleteVertexArrays(1, &renderer->glyph_vertex_array);
  if (renderer->overlay_vertex_array != 0) glDeleteVertexArrays(1, &renderer->overlay_vertex_array);
  if (renderer->cursor_vertex_array != 0) glDeleteVertexArrays(1, &renderer->cursor_vertex_array);
  if (renderer->program != 0) glDeleteProgram(renderer->program);
  if (renderer->glyph_program != 0) glDeleteProgram(renderer->glyph_program);
  if (renderer->overlay_program != 0) glDeleteProgram(renderer->overlay_program);
  if (renderer->cursor_program != 0) glDeleteProgram(renderer->cursor_program);
  if (renderer->command_region_program != 0) glDeleteProgram(renderer->command_region_program);
  renderer->cell_buffer = 0;
  renderer->glyph_buffer = 0;
  renderer->atlas_texture = 0;
  renderer->vertex_array = 0;
  renderer->glyph_vertex_array = 0;
  renderer->overlay_vertex_array = 0;
  renderer->cursor_vertex_array = 0;
  renderer->program = 0;
  renderer->glyph_program = 0;
  renderer->overlay_program = 0;
  renderer->cursor_program = 0;
  renderer->command_region_program = 0;
  renderer->cell_buffer_count = 0;
  renderer->glyph_buffer_count = 0;
  renderer->uploaded_atlas_generation = 0;
  renderer->uploaded_atlas_width = 0;
  renderer->uploaded_atlas_height = 0;
  renderer->atlas_uploaded = 0;
  renderer->rendered_revision = 0;
  if (renderer->pending.cells != NULL) renderer->pending.cells_full_upload = 1;
  if (renderer->pending.glyphs != NULL || renderer->pending.glyph_count == 0)
    renderer->pending.glyphs_dirty = 1;
}

static void kiwi_gtk_gl_upload_cells(KiwiGtkGlRenderer *renderer,
                                     KiwiGtkGlSnapshot *snapshot) {
  glBindBuffer(GL_ARRAY_BUFFER, renderer->cell_buffer);
  if (renderer->cell_buffer_count != snapshot->cell_count ||
      snapshot->cells_full_upload) {
    glBufferData(GL_ARRAY_BUFFER,
                 (GLsizeiptr)snapshot->cell_count * sizeof(KiwiGlyphInstance),
                 snapshot->cells, GL_DYNAMIC_DRAW);
    renderer->cell_full_uploads += 1;
    renderer->cell_buffer_count = snapshot->cell_count;
    memset(snapshot->cell_dirty, 0, snapshot->cell_count);
    snapshot->cells_full_upload = 0;
    snapshot->cells_dirty = 0;
  } else if (snapshot->cells_dirty) {
    uint32_t first = 0;
    while (first < snapshot->cell_count) {
      while (first < snapshot->cell_count && snapshot->cell_dirty[first] == 0) first += 1;
      uint32_t finish = first;
      while (finish < snapshot->cell_count && snapshot->cell_dirty[finish] != 0) finish += 1;
      if (finish > first) {
        glBufferSubData(GL_ARRAY_BUFFER,
                        (GLintptr)first * sizeof(KiwiGlyphInstance),
                        (GLsizeiptr)(finish - first) * sizeof(KiwiGlyphInstance),
                        snapshot->cells + first);
        renderer->cell_subrange_uploads += 1;
        renderer->cell_subrange_bytes +=
            (uint64_t)(finish - first) * sizeof(KiwiGlyphInstance);
        memset(snapshot->cell_dirty + first, 0, finish - first);
      }
      first = finish;
    }
    snapshot->cells_dirty = 0;
  }
  glBindBuffer(GL_ARRAY_BUFFER, 0);
}

static void kiwi_gtk_gl_upload_glyphs(KiwiGtkGlRenderer *renderer,
                                      KiwiGtkGlSnapshot *snapshot) {
  if (!snapshot->glyphs_dirty) return;
  glBindBuffer(GL_ARRAY_BUFFER, renderer->glyph_buffer);
  if (snapshot->glyph_count > 0) {
    glBufferData(GL_ARRAY_BUFFER,
                 (GLsizeiptr)snapshot->glyph_count * sizeof(KiwiTextGlyphInstance),
                 snapshot->glyphs, GL_DYNAMIC_DRAW);
    renderer->glyph_uploads += 1;
    renderer->glyph_upload_bytes +=
        (uint64_t)snapshot->glyph_count * sizeof(KiwiTextGlyphInstance);
  }
  renderer->glyph_buffer_count = snapshot->glyph_count;
  snapshot->glyphs_dirty = 0;
  glBindBuffer(GL_ARRAY_BUFFER, 0);
}

static int kiwi_gtk_gl_range_active(float start_column, float start_row,
                                    float finish_column, float finish_row,
                                    float alpha) {
  if (alpha <= 0) return 0;
  return finish_row > start_row ||
         (finish_row == start_row && finish_column > start_column);
}

static void kiwi_gtk_gl_draw_range(KiwiGtkGlRenderer *renderer,
                                   const KiwiGtkGlSnapshot *snapshot,
                                   float start_column, float start_row,
                                   float finish_column, float finish_row,
                                   float red, float green, float blue, float alpha) {
  if (!kiwi_gtk_gl_range_active(start_column, start_row, finish_column, finish_row, alpha)) return;
  glUseProgram(renderer->overlay_program);
  glUniform2f(glGetUniformLocation(renderer->overlay_program, "grid"),
              snapshot->frame.columns, snapshot->frame.rows);
  glUniform4f(glGetUniformLocation(renderer->overlay_program, "range"),
              start_column, start_row, finish_column, finish_row);
  glUniform4f(glGetUniformLocation(renderer->overlay_program, "overlay_color"),
              red, green, blue, alpha);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glBindVertexArray(renderer->overlay_vertex_array);
  glDrawArraysInstanced(GL_TRIANGLES, 0, 6, snapshot->cell_count);
  glBindVertexArray(0);
  glDisable(GL_BLEND);
  glUseProgram(0);
}

static void kiwi_gtk_gl_draw_cursor(KiwiGtkGlRenderer *renderer,
                                    const KiwiGtkGlSnapshot *snapshot) {
  const KiwiFrameUniform *frame = &snapshot->frame;
  if (frame->cursor_visible < 0.5 || frame->cursor_alpha <= 0 ||
      frame->cursor_column < 0 || frame->cursor_row < 0 ||
      frame->cursor_column >= frame->columns || frame->cursor_row >= frame->rows) return;
  glUseProgram(renderer->cursor_program);
  glUniform2f(glGetUniformLocation(renderer->cursor_program, "grid"),
              frame->columns, frame->rows);
  glUniform2f(glGetUniformLocation(renderer->cursor_program, "cursor_position"),
              frame->cursor_column, frame->cursor_row);
  glUniform4f(glGetUniformLocation(renderer->cursor_program, "cursor_color"),
              frame->cursor_red, frame->cursor_green, frame->cursor_blue,
              frame->cursor_alpha);
  glUniform1f(glGetUniformLocation(renderer->cursor_program, "cursor_visible"), frame->cursor_visible);
  glUniform1f(glGetUniformLocation(renderer->cursor_program, "cursor_shape"), frame->cursor_shape);
  glUniform1f(glGetUniformLocation(renderer->cursor_program, "cursor_blink"), frame->cursor_blink);
  glUniform1f(glGetUniformLocation(renderer->cursor_program, "frame_time"), frame->time);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glBindVertexArray(renderer->cursor_vertex_array);
  glDrawArrays(GL_TRIANGLES, 0, 6);
  glBindVertexArray(0);
  glDisable(GL_BLEND);
  glUseProgram(0);
}

static void kiwi_gtk_gl_draw_command_regions(KiwiGtkGlRenderer *renderer,
                                             const KiwiGtkGlSnapshot *snapshot) {
  const KiwiFrameUniform *frame = &snapshot->frame;
  int boundary_count = (int)frame->command_region_count;
  if (boundary_count < 1 || boundary_count > KIWI_RENDER_MODEL_COMMAND_REGION_LIMIT ||
      frame->command_region_alpha <= 0) return;
  glUseProgram(renderer->command_region_program);
  glUniform2f(glGetUniformLocation(renderer->command_region_program, "grid"),
              frame->columns, frame->rows);
  glUniform1i(glGetUniformLocation(renderer->command_region_program, "boundary_count"), boundary_count);
  glUniform4fv(glGetUniformLocation(renderer->command_region_program, "boundaries"),
               KIWI_RENDER_MODEL_COMMAND_REGION_LIMIT, frame->command_region_boundaries);
  glUniform4f(glGetUniformLocation(renderer->command_region_program, "command_region_color"),
              frame->command_region_red, frame->command_region_green,
              frame->command_region_blue, frame->command_region_alpha);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glBindVertexArray(renderer->overlay_vertex_array);
  glDrawArraysInstanced(GL_TRIANGLES, 0, 6, snapshot->cell_count);
  glBindVertexArray(0);
  glDisable(GL_BLEND);
  glUseProgram(0);
}

static void kiwi_gtk_gl_realize(GtkGLArea *area, gpointer userdata) {
  KiwiGtkGlRenderer *renderer = userdata;
  gtk_gl_area_make_current(area);
  GError *error = gtk_gl_area_get_error(area);
  if (error != NULL) {
    kiwi_gtk_gl_set_error(renderer, "GTK GL context creation failed: %s", error->message);
    return;
  }
  (void)kiwi_gtk_gl_create_resources(renderer);
}

static void kiwi_gtk_gl_unrealize(GtkGLArea *area, gpointer userdata) {
  KiwiGtkGlRenderer *renderer = userdata;
  gtk_gl_area_make_current(area);
  if (gtk_gl_area_get_error(area) == NULL) kiwi_gtk_gl_destroy_resources(renderer);
}

static gboolean kiwi_gtk_gl_render(GtkGLArea *area, GdkGLContext *context,
                                   gpointer userdata) {
  (void)context;
  KiwiGtkGlRenderer *renderer = userdata;
  gtk_gl_area_make_current(area);
  if (gtk_gl_area_get_error(area) != NULL) {
    kiwi_gtk_gl_set_error(renderer, "GTK GL render has no current context: %s",
                          gtk_gl_area_get_error(area)->message);
    return FALSE;
  }
  if (!kiwi_gtk_gl_create_resources(renderer)) return FALSE;
  int scale = gtk_widget_get_scale_factor(GTK_WIDGET(area));
  int width = gtk_widget_get_width(GTK_WIDGET(area));
  int height = gtk_widget_get_height(GTK_WIDGET(area));
  if (width < 1 || height < 1 || scale < 1) return TRUE;
  glViewport(0, 0, width * scale, height * scale);
  glClearColor(0.075f, 0.09f, 0.12f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);
  KiwiGtkGlSnapshot *snapshot = &renderer->pending;
  if (snapshot->cell_count == 0 || snapshot->frame.columns < 1 || snapshot->frame.rows < 1) return TRUE;
  kiwi_gtk_gl_upload_cells(renderer, snapshot);
  glUseProgram(renderer->program);
  GLint grid = glGetUniformLocation(renderer->program, "grid");
  glUniform2f(grid, snapshot->frame.columns, snapshot->frame.rows);
  glBindVertexArray(renderer->vertex_array);
  glDrawArraysInstanced(GL_TRIANGLES, 0, 6, snapshot->cell_count);
  glBindVertexArray(0);
  glUseProgram(0);
  kiwi_gtk_gl_draw_range(renderer, snapshot,
                         snapshot->frame.selection_start_column,
                         snapshot->frame.selection_start_row,
                         snapshot->frame.selection_finish_column,
                         snapshot->frame.selection_finish_row,
                         snapshot->frame.selection_red,
                         snapshot->frame.selection_green,
                         snapshot->frame.selection_blue,
                         snapshot->frame.selection_alpha);
  kiwi_gtk_gl_draw_range(renderer, snapshot,
                         snapshot->frame.search_start_column,
                         snapshot->frame.search_start_row,
                         snapshot->frame.search_finish_column,
                         snapshot->frame.search_finish_row,
                         snapshot->frame.search_red,
                         snapshot->frame.search_green,
                         snapshot->frame.search_blue,
                         snapshot->frame.search_alpha);
  kiwi_gtk_gl_draw_command_regions(renderer, snapshot);
  if (snapshot->glyph_count > 0 && snapshot->atlas_bytes > 0) {
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, renderer->atlas_texture);
    if (!renderer->atlas_uploaded ||
        renderer->uploaded_atlas_generation != snapshot->atlas_generation ||
        renderer->uploaded_atlas_width != snapshot->atlas_width ||
        renderer->uploaded_atlas_height != snapshot->atlas_height) {
      glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, snapshot->atlas_width, snapshot->atlas_height,
                   0, GL_RED, GL_UNSIGNED_BYTE, snapshot->atlas_pixels);
      renderer->uploaded_atlas_generation = snapshot->atlas_generation;
      renderer->uploaded_atlas_width = snapshot->atlas_width;
      renderer->uploaded_atlas_height = snapshot->atlas_height;
      renderer->atlas_uploaded = 1;
    }
    kiwi_gtk_gl_upload_glyphs(renderer, snapshot);
    glUseProgram(renderer->glyph_program);
    grid = glGetUniformLocation(renderer->glyph_program, "grid");
    glUniform2f(grid, snapshot->frame.columns, snapshot->frame.rows);
    glUniform1i(glGetUniformLocation(renderer->glyph_program, "alpha_atlas"), 0);
    glUniform4f(glGetUniformLocation(renderer->glyph_program, "hyperlink_color"),
                snapshot->frame.hyperlink_red, snapshot->frame.hyperlink_green,
                snapshot->frame.hyperlink_blue, snapshot->frame.hyperlink_alpha);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glBindVertexArray(renderer->glyph_vertex_array);
    glDrawArraysInstanced(GL_TRIANGLES, 0, 6, snapshot->glyph_count);
    glBindVertexArray(0);
    glDisable(GL_BLEND);
    glUseProgram(0);
    glBindTexture(GL_TEXTURE_2D, 0);
  }
  kiwi_gtk_gl_draw_cursor(renderer, snapshot);
  renderer->rendered_revision = snapshot->revision;
  return TRUE;
}

uint32_t kiwi_gtk_gl_renderer_abi_version(void) { return KIWI_GTK_GL_RENDERER_ABI_VERSION; }

int kiwi_gtk_gl_renderer_configure_area(GtkGLArea *area) {
  if (area == NULL || gtk_widget_get_realized(GTK_WIDGET(area))) return 0;
  gtk_gl_area_set_auto_render(area, FALSE);
  gtk_gl_area_set_has_depth_buffer(area, FALSE);
  gtk_gl_area_set_has_stencil_buffer(area, FALSE);
#if GTK_CHECK_VERSION(4, 12, 0)
  gtk_gl_area_set_allowed_apis(area, GDK_GL_API_GL);
#else
  gtk_gl_area_set_use_es(area, FALSE);
#endif
  gtk_gl_area_set_required_version(area, 3, 3);
  return 1;
}

KiwiGtkGlRenderer *kiwi_gtk_gl_renderer_new(GtkGLArea *area) {
  if (area == NULL) return NULL;
  KiwiGtkGlRenderer *renderer = g_new0(KiwiGtkGlRenderer, 1);
  renderer->area = area;
  renderer->realize_handler = g_signal_connect(area, "realize",
                                                G_CALLBACK(kiwi_gtk_gl_realize), renderer);
  renderer->render_handler = g_signal_connect(area, "render",
                                               G_CALLBACK(kiwi_gtk_gl_render), renderer);
  renderer->unrealize_handler = g_signal_connect(area, "unrealize",
                                                  G_CALLBACK(kiwi_gtk_gl_unrealize), renderer);
  return renderer;
}

void kiwi_gtk_gl_renderer_destroy(KiwiGtkGlRenderer *renderer) {
  if (renderer == NULL) return;
  if (renderer->area != NULL) {
    if (renderer->realize_handler != 0) g_signal_handler_disconnect(renderer->area, renderer->realize_handler);
    if (renderer->render_handler != 0) g_signal_handler_disconnect(renderer->area, renderer->render_handler);
    if (renderer->unrealize_handler != 0) g_signal_handler_disconnect(renderer->area, renderer->unrealize_handler);
    if (gtk_widget_get_realized(GTK_WIDGET(renderer->area))) {
      gtk_gl_area_make_current(renderer->area);
      if (gtk_gl_area_get_error(renderer->area) == NULL) kiwi_gtk_gl_destroy_resources(renderer);
    }
  }
  kiwi_gtk_gl_snapshot_clear(&renderer->pending);
  g_free(renderer);
}

int kiwi_gtk_gl_renderer_submit(KiwiGtkGlRenderer *renderer,
                                const KiwiGtkGlFrame *frame) {
  const uint32_t known_flags = KIWI_GTK_GL_FRAME_CELLS_FULL |
      KIWI_GTK_GL_FRAME_GLYPHS_UPDATED | KIWI_GTK_GL_FRAME_ATLAS_UPDATED;
  if (renderer == NULL || frame == NULL || frame->frame == NULL ||
      frame->render_model_version != KIWI_RENDER_MODEL_VERSION || frame->revision == 0 ||
      (frame->resource_flags & ~known_flags) != 0 ||
      frame->cell_count > KIWI_GTK_GL_MAX_CELLS ||
      frame->cell_update_count > KIWI_GTK_GL_MAX_CELL_UPDATES ||
      frame->glyph_count > KIWI_GTK_GL_MAX_GLYPHS ||
      frame->atlas_bytes > KIWI_GTK_GL_MAX_ATLAS_BYTES ||
      (frame->cell_update_count > 0 && frame->cell_updates == NULL) ||
      ((frame->resource_flags & KIWI_GTK_GL_FRAME_GLYPHS_UPDATED) != 0 &&
       frame->glyph_count > 0 && frame->glyphs == NULL) ||
      ((frame->resource_flags & KIWI_GTK_GL_FRAME_GLYPHS_UPDATED) == 0 &&
       frame->glyphs != NULL) ||
      ((frame->resource_flags & KIWI_GTK_GL_FRAME_ATLAS_UPDATED) != 0 &&
       frame->atlas_bytes > 0 && frame->atlas_pixels == NULL) ||
      ((frame->resource_flags & KIWI_GTK_GL_FRAME_ATLAS_UPDATED) == 0 &&
       (frame->atlas_pixels != NULL || frame->atlas_bytes != 0 ||
        frame->atlas_width != 0 || frame->atlas_height != 0 ||
        frame->atlas_generation != 0)) ||
      (frame->atlas_bytes > 0 && (frame->atlas_width == 0 || frame->atlas_height == 0))) {
    if (renderer != NULL) kiwi_gtk_gl_set_error(renderer, "GTK GL frame is invalid or exceeds a fixed resource bound");
    return 0;
  }
  if (frame->frame->columns < 1 || frame->frame->rows < 1 ||
      frame->frame->columns > KIWI_GTK_GL_MAX_CELLS ||
      frame->frame->rows > KIWI_GTK_GL_MAX_CELLS) {
    kiwi_gtk_gl_set_error(renderer, "GTK GL frame grid exceeds a fixed resource bound");
    return 0;
  }
  uint32_t columns = (uint32_t)frame->frame->columns;
  uint32_t rows = (uint32_t)frame->frame->rows;
  if (frame->frame->columns != (float)columns || frame->frame->rows != (float)rows ||
      (uint64_t)columns * rows != frame->cell_count ||
      (frame->atlas_bytes > 0 && (uint64_t)frame->atlas_width * frame->atlas_height != frame->atlas_bytes)) {
    kiwi_gtk_gl_set_error(renderer, "GTK GL frame is not a complete bounded grid/atlas snapshot");
    return 0;
  }
  if (frame->revision < renderer->pending.revision) {
    kiwi_gtk_gl_set_error(renderer, "GTK GL frame revision is older than the pending snapshot");
    return 0;
  }
  int cells_full = (frame->resource_flags & KIWI_GTK_GL_FRAME_CELLS_FULL) != 0;
  int glyphs_updated = (frame->resource_flags & KIWI_GTK_GL_FRAME_GLYPHS_UPDATED) != 0;
  int atlas_updated = (frame->resource_flags & KIWI_GTK_GL_FRAME_ATLAS_UPDATED) != 0;
  int replace_cells = renderer->pending.cells == NULL ||
      renderer->pending.cell_count != frame->cell_count;
  if ((replace_cells || cells_full) &&
      (frame->cell_update_count != 1 || frame->cell_updates[0].cells == NULL ||
       frame->cell_updates[0].first_cell != 0 ||
       frame->cell_updates[0].cell_count != frame->cell_count)) {
    kiwi_gtk_gl_set_error(renderer, "GTK GL grid initialization needs exactly one complete cell update");
    return 0;
  }
  if (replace_cells && !cells_full) {
    kiwi_gtk_gl_set_error(renderer, "GTK GL grid resize needs a complete cell update");
    return 0;
  }
  if (!glyphs_updated && frame->glyph_count != renderer->pending.glyph_count) {
    kiwi_gtk_gl_set_error(renderer, "GTK GL frame changed glyph resources without an update flag");
    return 0;
  }
  if (replace_cells && frame->glyph_count > 0 && !glyphs_updated) {
    kiwi_gtk_gl_set_error(renderer, "GTK GL grid initialization needs glyph resources");
    return 0;
  }
  if (glyphs_updated && frame->glyph_count > 0 && !atlas_updated &&
      renderer->pending.atlas_pixels == NULL) {
    kiwi_gtk_gl_set_error(renderer, "GTK GL glyph initialization needs atlas resources");
    return 0;
  }
  for (uint32_t index = 0; index < frame->cell_update_count; index += 1) {
    const KiwiGtkGlCellUpdate *update = &frame->cell_updates[index];
    if (update->cells == NULL || update->cell_count == 0 ||
        update->first_cell >= frame->cell_count ||
        (uint64_t)update->first_cell + update->cell_count > frame->cell_count) {
      kiwi_gtk_gl_set_error(renderer, "GTK GL cell update is outside the bounded grid");
      return 0;
    }
  }
  KiwiGlyphInstance *replacement_cells = NULL;
  uint8_t *replacement_dirty = NULL;
  KiwiTextGlyphInstance *replacement_glyphs = NULL;
  uint8_t *replacement_atlas = NULL;
  if (replace_cells) {
    replacement_cells = g_malloc((size_t)frame->cell_count * sizeof(*replacement_cells));
    replacement_dirty = g_malloc0(frame->cell_count);
    if (replacement_cells == NULL || replacement_dirty == NULL) goto allocation_failed;
  }
  if (glyphs_updated && frame->glyph_count > 0) {
    replacement_glyphs = kiwi_gtk_gl_copy(frame->glyphs,
                                          (size_t)frame->glyph_count * sizeof(*frame->glyphs));
    if (replacement_glyphs == NULL) goto allocation_failed;
  }
  if (atlas_updated && frame->atlas_bytes > 0) {
    replacement_atlas = kiwi_gtk_gl_copy(frame->atlas_pixels, frame->atlas_bytes);
    if (replacement_atlas == NULL) goto allocation_failed;
  }
  KiwiGtkGlSnapshot *snapshot = &renderer->pending;
  if (replace_cells) {
    g_free(snapshot->cells);
    g_free(snapshot->cell_dirty);
    snapshot->cells = replacement_cells;
    snapshot->cell_dirty = replacement_dirty;
    snapshot->cell_count = frame->cell_count;
    replacement_cells = NULL;
    replacement_dirty = NULL;
  }
  for (uint32_t index = 0; index < frame->cell_update_count; index += 1) {
    const KiwiGtkGlCellUpdate *update = &frame->cell_updates[index];
    memcpy(snapshot->cells + update->first_cell, update->cells,
           (size_t)update->cell_count * sizeof(*snapshot->cells));
    if (!cells_full) memset(snapshot->cell_dirty + update->first_cell, 1, update->cell_count);
  }
  if (cells_full) {
    memset(snapshot->cell_dirty, 0, snapshot->cell_count);
    snapshot->cells_full_upload = 1;
    snapshot->cells_dirty = 0;
  } else if (frame->cell_update_count > 0) {
    snapshot->cells_dirty = 1;
  }
  if (glyphs_updated) {
    g_free(snapshot->glyphs);
    snapshot->glyphs = replacement_glyphs;
    snapshot->glyph_count = frame->glyph_count;
    snapshot->glyphs_dirty = 1;
    replacement_glyphs = NULL;
  }
  if (atlas_updated) {
    g_free(snapshot->atlas_pixels);
    snapshot->atlas_pixels = replacement_atlas;
    snapshot->atlas_bytes = frame->atlas_bytes;
    snapshot->atlas_width = frame->atlas_width;
    snapshot->atlas_height = frame->atlas_height;
    snapshot->atlas_generation = frame->atlas_generation;
    replacement_atlas = NULL;
  }
  snapshot->frame = *frame->frame;
  snapshot->revision = frame->revision;
  renderer->error[0] = '\0';
  gtk_gl_area_queue_render(renderer->area);
  return 1;

allocation_failed:
  g_free(replacement_cells);
  g_free(replacement_dirty);
  g_free(replacement_glyphs);
  g_free(replacement_atlas);
  kiwi_gtk_gl_set_error(renderer, "GTK GL frame allocation failed");
  return 0;
}

const char *kiwi_gtk_gl_renderer_last_error(const KiwiGtkGlRenderer *renderer) {
  return renderer == NULL ? "GTK GL renderer is unavailable" : renderer->error;
}

uint64_t kiwi_gtk_gl_renderer_rendered_revision(const KiwiGtkGlRenderer *renderer) {
  return renderer == NULL ? 0 : renderer->rendered_revision;
}

void kiwi_gtk_gl_renderer_upload_metrics(const KiwiGtkGlRenderer *renderer,
                                         uint64_t *cell_full_uploads,
                                         uint64_t *cell_subrange_uploads,
                                         uint64_t *cell_subrange_bytes,
                                         uint64_t *glyph_uploads,
                                         uint64_t *glyph_upload_bytes) {
  if (cell_full_uploads != NULL)
    *cell_full_uploads = renderer == NULL ? 0 : renderer->cell_full_uploads;
  if (cell_subrange_uploads != NULL)
    *cell_subrange_uploads = renderer == NULL ? 0 : renderer->cell_subrange_uploads;
  if (cell_subrange_bytes != NULL)
    *cell_subrange_bytes = renderer == NULL ? 0 : renderer->cell_subrange_bytes;
  if (glyph_uploads != NULL)
    *glyph_uploads = renderer == NULL ? 0 : renderer->glyph_uploads;
  if (glyph_upload_bytes != NULL)
    *glyph_upload_bytes = renderer == NULL ? 0 : renderer->glyph_upload_bytes;
}
