#ifndef KIWI_RENDER_MODEL_H
#define KIWI_RENDER_MODEL_H

#include <stddef.h>
#include <stdint.h>

enum {
  KIWI_RENDER_MODEL_VERSION = 1,
  KIWI_RENDER_MODEL_COMMAND_REGION_LIMIT = 32,
};

typedef struct KiwiGlyphInstance {
  float x;
  float y;
  float u0;
  float v0;
  float u1;
  float v1;
  uint32_t fg;
  uint32_t bg;
  uint32_t flags;
  uint32_t glyph;
} KiwiGlyphInstance;

typedef struct KiwiTextGlyphInstance {
  float x;
  float y;
  float width;
  float height;
  float u0;
  float v0;
  float u1;
  float v1;
  uint32_t fg;
  uint32_t flags;
  uint32_t glyph;
  uint32_t cluster;
} KiwiTextGlyphInstance;

typedef struct KiwiImageInstance {
  float x;
  float y;
  float width;
  float height;
  float u0;
  float v0;
  float u1;
  float v1;
} KiwiImageInstance;

typedef struct KiwiFrameUniform {
  float columns;
  float rows;
  float cursor_column;
  float cursor_row;
  float time;
  float show_dirty;
  float show_boundaries;
  float cursor_visible;
  float cursor_shape;
  float cursor_blink;
  float cursor_red;
  float cursor_green;
  float cursor_blue;
  float cursor_alpha;
  float selection_start_column;
  float selection_start_row;
  float selection_finish_column;
  float selection_finish_row;
  float selection_red;
  float selection_green;
  float selection_blue;
  float selection_alpha;
  float search_start_column;
  float search_start_row;
  float search_finish_column;
  float search_finish_row;
  float search_red;
  float search_green;
  float search_blue;
  float search_alpha;
  float hyperlink_red;
  float hyperlink_green;
  float hyperlink_blue;
  float hyperlink_alpha;
  float command_region_count;
  float command_region_red;
  float command_region_green;
  float command_region_blue;
  float command_region_alpha;
  float command_region_padding[5];
  float command_region_boundaries[KIWI_RENDER_MODEL_COMMAND_REGION_LIMIT * 4];
} KiwiFrameUniform;

_Static_assert(sizeof(KiwiGlyphInstance) == 40, "KiwiGlyphInstance ABI changed");
_Static_assert(offsetof(KiwiGlyphInstance, fg) == 24, "KiwiGlyphInstance field ABI changed");
_Static_assert(sizeof(KiwiTextGlyphInstance) == 48, "KiwiTextGlyphInstance ABI changed");
_Static_assert(offsetof(KiwiTextGlyphInstance, fg) == 32, "KiwiTextGlyphInstance field ABI changed");
_Static_assert(sizeof(KiwiImageInstance) == 32, "KiwiImageInstance ABI changed");
_Static_assert(sizeof(KiwiFrameUniform) == 688, "KiwiFrameUniform ABI changed");
_Static_assert(offsetof(KiwiFrameUniform, command_region_boundaries) == 176,
               "KiwiFrameUniform boundary ABI changed");

#endif
