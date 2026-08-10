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
]]

local Packing = {
  glyph_instance_size = ffi.sizeof("KiwiGlyphInstance"),
  glyph_instance_alignment = ffi.alignof("KiwiGlyphInstance"),
  text_glyph_instance_size = ffi.sizeof("KiwiTextGlyphInstance"),
  text_glyph_instance_alignment = ffi.alignof("KiwiTextGlyphInstance"),
  image_instance_size = ffi.sizeof("KiwiImageInstance"),
  image_instance_alignment = ffi.alignof("KiwiImageInstance"),
}

function Packing.assert_layout()
  assert(Packing.glyph_instance_size == 40, "KiwiGlyphInstance must remain 40 bytes")
  assert(Packing.glyph_instance_alignment == 4, "KiwiGlyphInstance must remain 4-byte aligned")
  assert(Packing.text_glyph_instance_size == 48, "KiwiTextGlyphInstance must remain 48 bytes")
  assert(Packing.text_glyph_instance_alignment == 4, "KiwiTextGlyphInstance must remain 4-byte aligned")
  assert(Packing.image_instance_size == 32, "KiwiImageInstance must remain 32 bytes")
  assert(Packing.image_instance_alignment == 4, "KiwiImageInstance must remain 4-byte aligned")
end

function Packing.bytes_for_cells(cells)
  return cells * Packing.glyph_instance_size
end

return Packing
