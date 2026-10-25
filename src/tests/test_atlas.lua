local Assert = require("tests.assert")
local Atlas = require("kiwi.font.atlas")

return {
  atlas_reclaims_space_without_moving_live_glyphs = function()
    local atlas = Atlas.new(16, 16, 1)
    local first = atlas:insert("A", 6, 6)
    local second = atlas:insert("B", 6, 6)
    atlas:insert("C", 6, 6)
    atlas:insert("D", 6, 6)
    Assert.equal(atlas:try_insert("E", 6, 6), nil)
    Assert.truthy(atlas:remove("A"))
    local replacement = atlas:insert("E", 6, 6)
    Assert.equal(replacement.x, first.x)
    Assert.equal(replacement.y, first.y)
    Assert.equal(atlas:get("B"), second)
    Assert.equal(second.x, 9)
    for _, key in ipairs({ "B", "C", "D", "E" }) do atlas:remove(key) end
    Assert.equal(atlas:glyph_count(), 0)
    Assert.equal(atlas:occupancy(), 0)
    local full = atlas:insert("full", 14, 14)
    Assert.equal(full.x, 1)
    Assert.equal(full.y, 1)
    Assert.equal(atlas:remove("missing"), false)
  end,
  atlas_rejects_oversize_without_consuming_space = function()
    local atlas = Atlas.new(8, 8, 1)
    Assert.equal(atlas:try_insert("wide", 7, 1), nil)
    Assert.equal(atlas:try_insert("tall", 1, 7), nil)
    Assert.equal(atlas:glyph_count(), 0)
    Assert.truthy(atlas:insert("fits", 6, 6))
  end,
  atlas_churn_preserves_nonoverlapping_allocations_and_coalesces = function()
    local atlas = Atlas.new(64, 64, 1)
    local live = {}
    for index = 1, 2000 do
      local key = tostring(index)
      local glyph = atlas:try_insert(key, 2 + index % 11, 2 + index % 9)
      if glyph then
        for _, other in pairs(live) do
          local a, b = glyph.allocation, other.allocation
          Assert.truthy(a.x + a.width <= b.x or b.x + b.width <= a.x or a.y + a.height <= b.y or b.y + b.height <= a.y)
        end
        live[key] = glyph
      end
      if not glyph or index % 3 == 0 then
        local oldest
        for old in pairs(live) do if not oldest or tonumber(old) < tonumber(oldest) then oldest = old end end
        if oldest then atlas:remove(oldest); live[oldest] = nil end
      end
    end
    for key in pairs(live) do atlas:remove(key) end
    Assert.truthy(atlas:insert("whole", 62, 62))
  end,
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
