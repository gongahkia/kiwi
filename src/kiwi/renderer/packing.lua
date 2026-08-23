local ffi = require("ffi")
local RenderModel = require("kiwi.renderer.render_model")

local Packing = {
  glyph_instance_size = ffi.sizeof("KiwiGlyphInstance"),
  glyph_instance_alignment = ffi.alignof("KiwiGlyphInstance"),
  text_glyph_instance_size = ffi.sizeof("KiwiTextGlyphInstance"),
  text_glyph_instance_alignment = ffi.alignof("KiwiTextGlyphInstance"),
  image_instance_size = ffi.sizeof("KiwiImageInstance"),
  image_instance_alignment = ffi.alignof("KiwiImageInstance"),
}

function Packing.assert_layout()
  RenderModel.assert_layout()
  assert(Packing.glyph_instance_alignment == 4, "KiwiGlyphInstance ABI alignment changed")
  assert(Packing.text_glyph_instance_alignment == 4, "KiwiTextGlyphInstance ABI alignment changed")
  assert(Packing.image_instance_alignment == 4, "KiwiImageInstance ABI alignment changed")
end

function Packing.bytes_for_cells(cells)
  return cells * Packing.glyph_instance_size
end

return Packing
