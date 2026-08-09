local Assert = require("tests.assert")
local FreeType = require("kiwi.font.freetype")

return {
  freetype_rasterizes_basic_latin_into_a_real_atlas = function()
    local font = FreeType.rasterize({ pixel_height = 18, atlas_width = 256, atlas_height = 256 })
    Assert.equal(font.atlas:glyph_count(), 95)
    Assert.truthy(font.atlas:get("A").width > 0)
    Assert.truthy(font.atlas:get("A").bitmap.advance > 0)
    Assert.truthy(font.atlas:occupancy() > 0)
    Assert.truthy(font.cell_width > 0)
    Assert.truthy(font.cell_height > font.pixel_height)
  end,
}
