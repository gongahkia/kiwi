local ffi = require("ffi")
require("kiwi.ffi.freetype")

ffi.cdef[[
typedef struct hb_font_t hb_font_t;
typedef struct hb_buffer_t hb_buffer_t;
typedef unsigned int hb_codepoint_t;
typedef unsigned int hb_mask_t;
typedef int hb_position_t;
typedef struct {
  hb_codepoint_t codepoint;
  hb_mask_t mask;
  uint32_t cluster;
  uint32_t var1;
  uint32_t var2;
} hb_glyph_info_t;
typedef struct {
  hb_position_t x_advance;
  hb_position_t y_advance;
  hb_position_t x_offset;
  hb_position_t y_offset;
  uint32_t var;
} hb_glyph_position_t;
typedef struct {
  uint32_t tag;
  uint32_t value;
  unsigned int start;
  unsigned int end;
} hb_feature_t;
hb_font_t *hb_ft_font_create_referenced(FT_Face ft_face);
void hb_font_destroy(hb_font_t *font);
hb_buffer_t *hb_buffer_create(void);
void hb_buffer_destroy(hb_buffer_t *buffer);
void hb_buffer_reset(hb_buffer_t *buffer);
void hb_buffer_add_utf8(hb_buffer_t *buffer, const char *text, int text_length, unsigned int item_offset, int item_length);
void hb_buffer_set_direction(hb_buffer_t *buffer, int direction);
void hb_buffer_set_cluster_level(hb_buffer_t *buffer, int cluster_level);
void hb_buffer_set_script(hb_buffer_t *buffer, uint32_t script);
void hb_buffer_set_language(hb_buffer_t *buffer, const void *language);
void hb_buffer_guess_segment_properties(hb_buffer_t *buffer);
unsigned int hb_buffer_get_length(const hb_buffer_t *buffer);
hb_glyph_info_t *hb_buffer_get_glyph_infos(hb_buffer_t *buffer, unsigned int *length);
hb_glyph_position_t *hb_buffer_get_glyph_positions(hb_buffer_t *buffer, unsigned int *length);
uint32_t hb_script_from_string(const char *str, int len);
const void *hb_language_from_string(const char *str, int len);
void hb_shape(hb_font_t *font, hb_buffer_t *buffer, const hb_feature_t *features, unsigned int num_features);
const char *hb_version_string(void);
]]

local ok, harfbuzz = pcall(ffi.load, "harfbuzz")
if not ok then
  error("Unable to load HarfBuzz. Install harfbuzz-devel (Fedora): " .. tostring(harfbuzz))
end

return {
  ffi = ffi,
  lib = harfbuzz,
  direction_ltr = 4,
  cluster_level_monotone_graphemes = 0,
  feature_global_end = 0xffffffff,
}
