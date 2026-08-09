local Assert = require("tests.assert")
local Atlas = require("kiwi.font.atlas")

return {
  glyph_atlas_uses_shelves_and_tracks_uvs = function()
    local atlas = Atlas.new(32, 32, 1)
    local a = atlas:insert("A", 8, 10, "bitmap-a")
    local b = atlas:insert("B", 8, 10, "bitmap-b")
    Assert.equal(a.x, 1)
    Assert.equal(b.x, 11)
    Assert.equal(atlas:glyph_count(), 2)
    Assert.truthy(a.u0 < a.u1)
    Assert.truthy(a.v0 < a.v1)
    Assert.near(atlas:occupancy(), 160 / 1024, 0.000001)
  end,
}
