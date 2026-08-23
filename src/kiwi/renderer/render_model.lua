-- ABI v2 shared by renderer-neutral LuaJIT producers and native presentation
-- consumers. Keep this definition identical to native/kiwi_render_model.h.
local ffi = require("ffi")

ffi.cdef[[
typedef struct {
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
typedef struct {
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
typedef struct {
  float x;
  float y;
  float width;
  float height;
  float u0;
  float v0;
  float u1;
  float v1;
} KiwiImageInstance;
typedef struct {
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
  float command_region_boundaries[128];
  float scrollbar_visible;
  float scrollbar_left;
  float scrollbar_right;
  float scrollbar_top;
  float scrollbar_bottom;
  float scrollbar_red;
  float scrollbar_green;
  float scrollbar_blue;
  float scrollbar_alpha;
  float scrollbar_padding[3];
} KiwiFrameUniform;
]]

local RenderModel = {
  command_region_limit = 32,
  version = 2,
}

function RenderModel.assert_layout()
  assert(ffi.sizeof("KiwiGlyphInstance") == 40, "KiwiGlyphInstance ABI changed")
  assert(ffi.offsetof("KiwiGlyphInstance", "fg") == 24, "KiwiGlyphInstance field ABI changed")
  assert(ffi.sizeof("KiwiTextGlyphInstance") == 48, "KiwiTextGlyphInstance ABI changed")
  assert(ffi.offsetof("KiwiTextGlyphInstance", "fg") == 32, "KiwiTextGlyphInstance field ABI changed")
  assert(ffi.sizeof("KiwiImageInstance") == 32, "KiwiImageInstance ABI changed")
  assert(ffi.sizeof("KiwiFrameUniform") == 736, "KiwiFrameUniform ABI changed")
  assert(ffi.offsetof("KiwiFrameUniform", "command_region_boundaries") == 176,
    "KiwiFrameUniform boundary ABI changed")
end

return RenderModel
