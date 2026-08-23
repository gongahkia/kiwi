#ifndef KIWI_GTK_GL_RENDERER_H
#define KIWI_GTK_GL_RENDERER_H

#include <gtk/gtk.h>

#include "kiwi_render_model.h"

typedef struct KiwiGtkGlRenderer KiwiGtkGlRenderer;

#define KIWI_GTK_GL_RENDERER_ABI_VERSION 3u

enum {
  /* The first frame for a grid, and every resize, replaces all cell data. */
  KIWI_GTK_GL_FRAME_CELLS_FULL = 1u << 0,
  /* Glyph and atlas resources are retained until their generation changes. */
  KIWI_GTK_GL_FRAME_GLYPHS_UPDATED = 1u << 1,
  KIWI_GTK_GL_FRAME_ATLAS_UPDATED = 1u << 2,
};

typedef struct KiwiGtkGlCellUpdate {
  const KiwiGlyphInstance *cells;
  uint32_t first_cell;
  uint32_t cell_count;
} KiwiGtkGlCellUpdate;

typedef struct KiwiGtkGlFrame {
  uint32_t render_model_version;
  uint64_t revision;
  const KiwiGtkGlCellUpdate *cell_updates;
  uint32_t cell_update_count;
  uint32_t cell_count;
  const KiwiTextGlyphInstance *glyphs;
  uint32_t glyph_count;
  const uint8_t *atlas_pixels;
  uint32_t atlas_bytes;
  uint32_t atlas_width;
  uint32_t atlas_height;
  uint64_t atlas_generation;
  const KiwiFrameUniform *frame;
  uint32_t resource_flags;
} KiwiGtkGlFrame;

uint32_t kiwi_gtk_gl_renderer_abi_version(void);
/* Configure a fresh GtkGLArea before it is parented or realized. */
int kiwi_gtk_gl_renderer_configure_area(GtkGLArea *area);
KiwiGtkGlRenderer *kiwi_gtk_gl_renderer_new(GtkGLArea *area);
void kiwi_gtk_gl_renderer_destroy(KiwiGtkGlRenderer *renderer);
int kiwi_gtk_gl_renderer_submit(KiwiGtkGlRenderer *renderer,
                                const KiwiGtkGlFrame *frame);
const char *kiwi_gtk_gl_renderer_last_error(const KiwiGtkGlRenderer *renderer);
uint64_t kiwi_gtk_gl_renderer_rendered_revision(const KiwiGtkGlRenderer *renderer);
void kiwi_gtk_gl_renderer_upload_metrics(const KiwiGtkGlRenderer *renderer,
                                         uint64_t *cell_full_uploads,
                                         uint64_t *cell_subrange_uploads,
                                         uint64_t *cell_subrange_bytes,
                                         uint64_t *glyph_uploads,
                                         uint64_t *glyph_upload_bytes);

#endif
