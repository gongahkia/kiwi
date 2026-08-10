local Assert = require("tests.assert")
local Packing = require("kiwi.renderer.packing")

return {
  glyph_instance_layout_is_deliberate = function()
    Packing.assert_layout()
    Assert.equal(Packing.glyph_instance_size, 40)
    Assert.equal(Packing.text_glyph_instance_size, 48)
    Assert.equal(Packing.image_instance_size, 32)
    Assert.equal(Packing.bytes_for_cells(8000), 320000)
  end,
}
