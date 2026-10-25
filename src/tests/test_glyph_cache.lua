local ffi = require("ffi")
local Assert = require("tests.assert")
local Cache = require("kiwi.font.glyph_cache")

local function fixture(options)
  local face = { id = 1, pixel_height = 8, native = { pixel_mode_gray = 2, pixel_mode_bgra = 7 }, calls = 0 }
  function face:rasterize(id)
    self.calls = self.calls + 1
    self.buffer = ffi.new("uint8_t[16]", id % 256)
    return { width = 4, height = 4, pitch = 4, buffer = self.buffer, pixel_mode = 2, left = 0, top = 4 }
  end
  return Cache.new(options or { width = 12, height = 6, max_entries = 2 }), face
end

return {
  cache_evicts_least_recently_used_unpinned_glyph_and_clears_padding = function()
    local cache, face = fixture()
    local a = assert(cache:get_or_insert(face, 1))
    local b = assert(cache:get_or_insert(face, 2))
    cache:get_or_insert(face, 1)
    local c = assert(cache:get_or_insert(face, 3))
    Assert.equal(cache.entries[a.key], a)
    Assert.equal(cache.entries[b.key], nil)
    Assert.equal(c.x, b.x)
    Assert.equal(cache.atlas:glyph_count(), 2)
    Assert.equal(tonumber(cache.pixels[c.y * cache.atlas.width + c.x]), 3)
    Assert.equal(tonumber(cache.pixels[(c.y - 1) * cache.atlas.width + c.x - 1]), 0)
    Assert.equal(cache.stats.evictions, 1)
  end,
  capacity_failure_recovers_after_owner_releases_and_never_poisoned_negative_cache = function()
    local cache, face = fixture()
    local pane = {}
    local a = assert(cache:get_or_insert(face, 1, pane))
    assert(cache:get_or_insert(face, 2, pane))
    local missing, reason = cache:get_or_insert(face, 3, pane)
    Assert.equal(missing, nil)
    Assert.equal(reason, "entry-limit")
    Assert.equal(cache.failure_count, 0)
    cache:retain(pane, { { cache_entry = a } })
    Assert.truthy(cache:get_or_insert(face, 3, pane))
    Assert.equal(cache.entries[a.key], a)
  end,
  page_exhaustion_recovers_and_other_panes_remain_pinned = function()
    local cache, face = fixture({ width = 12, height = 6, max_entries = 10 })
    local left, right = {}, {}
    local a = assert(cache:get_or_insert(face, 1, left))
    assert(cache:get_or_insert(face, 2, right))
    local missing, reason = cache:get_or_insert(face, 3, right)
    Assert.equal(missing, nil)
    Assert.equal(reason, "atlas-full")
    cache:retain(right, {})
    for id = 3, 500 do
      cache:retain(right, {})
      Assert.truthy(cache:get_or_insert(face, id, right))
      Assert.equal(cache.entries[a.key], a)
      Assert.equal(tonumber(cache.pixels[a.y * cache.atlas.width + a.x]), 1)
    end
    Assert.equal(cache.atlas:glyph_count(), 2)
    Assert.equal(cache.pixel_bytes, 72)
    Assert.equal(cache.failure_count, 0)
  end,
  unreachable_layout_owners_do_not_pin_glyphs_forever = function()
    local cache, face = fixture()
    do
      local owner = {}
      assert(cache:get_or_insert(face, 1, owner))
      assert(cache:get_or_insert(face, 2, owner))
    end
    collectgarbage("collect")
    collectgarbage("collect")
    Assert.truthy(cache:get_or_insert(face, 3))
  end,
  impossible_bitmap_does_not_evict_usable_glyphs = function()
    local cache, face = fixture()
    local a = assert(cache:get_or_insert(face, 1))
    function face:rasterize() return { width = 100, height = 1, pitch = 100, pixel_mode = 2 } end
    local missing, reason = cache:get_or_insert(face, 2)
    Assert.equal(missing, nil)
    Assert.equal(reason, "bitmap-limit")
    Assert.equal(cache.entries[a.key], a)
    Assert.equal(cache.stats.evictions, 0)
    Assert.equal(cache:get_or_insert(face, 2), nil)
    Assert.equal(cache.stats.negative_hits, 1)
  end,
}
