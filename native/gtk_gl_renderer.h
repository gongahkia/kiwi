#ifndef KIWI_GTK_GL_RENDERER_H
#define KIWI_GTK_GL_RENDERER_H

#include <gtk/gtk.h>

#include "kiwi_render_model.h"

typedef struct KiwiGtkGlRenderer KiwiGtkGlRenderer;

typedef struct KiwiGtkGlFrame {
  uint32_t render_model_version;
  uint64_t revision;
  const KiwiGlyphInstance *cells;
  uint32_t cell_count;
  const KiwiTextGlyphInstance *glyphs;
  uint32_t glyph_count;
  const uint8_t *atlas_pixels;
  uint32_t atlas_bytes;
  uint32_t atlas_width;
  uint32_t atlas_height;
  const KiwiFrameUniform *frame;
} KiwiGtkGlFrame;

uint32_t kiwi_gtk_gl_renderer_abi_version(void);
KiwiGtkGlRenderer *kiwi_gtk_gl_renderer_new(GtkGLArea *area);
void kiwi_gtk_gl_renderer_destroy(KiwiGtkGlRenderer *renderer);
int kiwi_gtk_gl_renderer_submit(KiwiGtkGlRenderer *renderer,
                                const KiwiGtkGlFrame *frame);
const char *kiwi_gtk_gl_renderer_last_error(const KiwiGtkGlRenderer *renderer);
uint64_t kiwi_gtk_gl_renderer_rendered_revision(const KiwiGtkGlRenderer *renderer);

#endif
