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
]]

local Packing = {
  glyph_instance_size = ffi.sizeof("KiwiGlyphInstance"),
  glyph_instance_alignment = ffi.alignof("KiwiGlyphInstance"),
}

function Packing.assert_layout()
  assert(Packing.glyph_instance_size == 40, "KiwiGlyphInstance must remain 40 bytes")
  assert(Packing.glyph_instance_alignment == 4, "KiwiGlyphInstance must remain 4-byte aligned")
end

function Packing.bytes_for_cells(cells)
  return cells * Packing.glyph_instance_size
end

return Packing
