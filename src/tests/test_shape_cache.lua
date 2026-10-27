local Assert = require("tests.assert")
local Cache = require("kiwi.text.shape_cache")

local function face(count)
  return { id = 1, calls = 0, shape = function(self, text)
    self.calls = self.calls + 1
    local glyphs = {}
    for index = 1, count or #text do
      glyphs[index] = { glyph_id = text:byte(1), cluster = index - 1,
        x_advance = 64, y_advance = 0, x_offset = 0, y_offset = 0 }
    end
    return glyphs
  end }
end

return {
  shape_cache_keys_exact_text_and_face_identity = function()
    local cache, first, second = Cache.new(), face(), face()
    local original, hit = cache:shape(first, "ab", {})
    Assert.equal(hit, false)
    local repeated, repeated_hit = cache:shape(first, "ab", {})
    Assert.equal(repeated, original)
    Assert.equal(repeated_hit, true)
    Assert.equal(first.calls, 1)
    Assert.equal(select(2, cache:shape(first, "ba", {})), false)
    Assert.equal(select(2, cache:shape(second, "ab", {})), false)
    Assert.equal(second.calls, 1)
    Assert.equal(cache.count, 3)
  end,
  shape_cache_invalidates_each_option_including_mutated_option_tables = function()
    local cache, font, options = Cache.new(), face(), {}
    cache:shape(font, "fi", options)
    for _, change in ipairs({ { "ligatures", true }, { "contextual_alternates", true },
        { "script", "Latn" }, { "language", "tr" }, { "ligatures", false } }) do
      options[change[1]] = change[2]
      Assert.equal(select(2, cache:shape(font, "fi", options)), false)
      Assert.equal(select(2, cache:shape(font, "fi", options)), true)
      Assert.equal(cache.count, 1)
    end
    Assert.equal(font.calls, 6)
    cache:clear()
    Assert.equal(cache.count, 0)
    Assert.equal(next(cache.faces), nil)
    Assert.equal(next(cache.order), nil)
    Assert.equal(select(2, cache:shape(font, "fi", options)), false)
  end,
  shape_cache_fifo_bounds_entries_bytes_glyphs_and_face_references = function()
    for _, size in ipairs({ 1, 200, 1000 }) do
      local cache, font = Cache.new(), face(size == 1000 and 1 or size)
      local first = cache:shape(font, string.rep("A", size), {})
      for index = 1, 600 do
        -- Distinct face objects also exercise removal of empty face buckets.
        local current = index % 2 == 0 and face(size == 1000 and 1 or size) or font
        cache:shape(current, tostring(index) .. string.rep("B", size - 1), {})
        Assert.truthy(cache.count <= Cache.maximum_entries)
        Assert.truthy(cache.text_bytes <= Cache.maximum_text_bytes)
        Assert.truthy(cache.glyph_count <= Cache.maximum_glyphs)
      end
      local faces, entries, bytes, glyphs = 0, 0, 0, 0
      for _, bucket in pairs(cache.faces) do
        faces = faces + 1
        Assert.truthy(next(bucket))
        for text, entry in pairs(bucket) do
          entries, bytes, glyphs = entries + 1, bytes + #text, glyphs + #entry.glyphs
        end
      end
      Assert.truthy(faces <= cache.count)
      Assert.equal(entries, cache.count)
      Assert.equal(bytes, cache.text_bytes)
      Assert.equal(glyphs, cache.glyph_count)
      Assert.equal(select(2, cache:shape(font, string.rep("A", size), {})), false)
      Assert.equal(first[1].glyph_id, string.byte("A"))
    end
  end,
  shape_cache_does_not_truncate_or_retain_oversized_runs = function()
    local cache, font = Cache.new(), face()
    local text = string.rep("x", Cache.maximum_run_bytes + 1)
    for _ = 1, 2 do
      local shaped, hit = cache:shape(font, text, {})
      Assert.equal(#shaped, #text)
      Assert.equal(hit, false)
    end
    local expanded = face(Cache.maximum_run_glyphs + 1)
    Assert.equal(#cache:shape(expanded, "x", {}), Cache.maximum_run_glyphs + 1)
    Assert.equal(cache.count, 0)
    Assert.equal(cache.text_bytes, 0)
    Assert.equal(cache.glyph_count, 0)
  end,
  shape_cache_repeated_hits_avoid_per_glyph_allocation = function()
    local cache, font, options = Cache.new(), face(128), {}
    local expected = cache:shape(font, "repeat", options)
    for _ = 1, 100 do cache:shape(font, "repeat", options) end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local ok, failure = pcall(function()
      for _ = 1, 20000 do Assert.equal(cache:shape(font, "repeat", options), expected) end
      Assert.truthy(collectgarbage("count") - before < 128, "cached shapes allocated more than 128 KiB")
      Assert.equal(font.calls, 1)
    end)
    collectgarbage("restart")
    if not ok then error(failure) end
  end,
}
