local ffi = require("ffi")
local Atlas = require("kiwi.font.atlas")

local GlyphCache = {}
GlyphCache.__index = GlyphCache

local function key_for(face, glyph_id)
  return table.concat({ face.id, glyph_id, face.pixel_height, "gray" }, ":")
end

function GlyphCache.new(options)
  options = options or {}
  local width = options.width or 1024
  local height = options.height or 1024
  return setmetatable({
    atlas = Atlas.new(width, height, options.padding or 1),
    pixels = ffi.new("uint8_t[?]", width * height),
    pixel_bytes = width * height,
    max_entries = options.max_entries or 8192,
    max_failure_entries = options.max_failure_entries or options.max_entries or 8192,
    max_bitmap_dimension = options.max_bitmap_dimension or 512,
    entries = {},
    failures_by_key = {},
    failure_count = 0,
    owner_glyphs = setmetatable({}, { __mode = "k" }),
    availability_generation = 0,
    generation = 0,
    stats = { hits = 0, misses = 0, failures = 0, negative_hits = 0, color_unsupported = 0, evictions = 0, capacity_failures = 0 },
  }, GlyphCache)
end

function GlyphCache:remember_failure(key, reason)
  if self.failure_count < self.max_failure_entries and self.failures_by_key[key] == nil then
    self.failures_by_key[key] = reason
    self.failure_count = self.failure_count + 1
  end
  self.stats.failures = self.stats.failures + 1
  return nil, reason
end

function GlyphCache:unlink(glyph)
  if glyph.previous then glyph.previous.next = glyph.next else self.oldest = glyph.next end
  if glyph.next then glyph.next.previous = glyph.previous else self.newest = glyph.previous end
  glyph.previous, glyph.next = nil, nil
end

function GlyphCache:touch(glyph, owner)
  if self.newest ~= glyph then
    if glyph.previous or glyph.next or self.oldest == glyph then self:unlink(glyph) end
    glyph.previous = self.newest
    if self.newest then self.newest.next = glyph else self.oldest = glyph end
    self.newest = glyph
  end
  if owner then
    local owned = self.owner_glyphs[owner]
    if not owned then owned = {}; self.owner_glyphs[owner] = owned end
    owned[glyph] = true
    glyph.owners[owner] = true
  end
end

-- Layouts retain every glyph referenced by unchanged rows before inserting
-- new text. Other panes' live coordinates stay valid even during eviction.
function GlyphCache:retain(owner, glyphs)
  local retained = {}
  for _, glyph in ipairs(glyphs) do
    local entry = glyph.cache_entry
    if entry then retained[entry] = true; entry.owners[owner] = true end
  end
  local released = false
  for entry in pairs(self.owner_glyphs[owner] or {}) do
    if not retained[entry] then entry.owners[owner] = nil; released = true end
  end
  self.owner_glyphs[owner] = next(retained) and retained or nil
  if released then self.availability_generation = self.availability_generation + 1 end
end

function GlyphCache:evict_one()
  local glyph = self.oldest
  while glyph and next(glyph.owners) do glyph = glyph.next end
  if not glyph then return false end
  self:unlink(glyph)
  self.entries[glyph.key] = nil
  self.atlas:remove(glyph.key)
  self.stats.evictions = self.stats.evictions + 1
  self.availability_generation = self.availability_generation + 1
  return true
end

function GlyphCache:get_or_insert(face, glyph_id, owner)
  if glyph_id == 0 then
    self.stats.failures = self.stats.failures + 1
    return nil, "missing-glyph"
  end
  local key = key_for(face, glyph_id)
  local existing = self.entries[key]
  if existing then
    self.stats.hits = self.stats.hits + 1
    self:touch(existing, owner)
    return existing
  end
  local failed = self.failures_by_key[key]
  if failed then
    self.stats.negative_hits = self.stats.negative_hits + 1
    return nil, failed
  end
  self.stats.misses = self.stats.misses + 1
  local bitmap = face:rasterize(glyph_id)
  if bitmap.pixel_mode ~= face.native.pixel_mode_gray then
    if bitmap.pixel_mode == face.native.pixel_mode_bgra then self.stats.color_unsupported = self.stats.color_unsupported + 1 end
    return self:remember_failure(key, "unsupported-pixel-mode")
  end
  if bitmap.width > self.max_bitmap_dimension or bitmap.height > self.max_bitmap_dimension or bitmap.pitch <= 0 then
    return self:remember_failure(key, "bitmap-limit")
  end
  if bitmap.width == 0 or bitmap.height == 0 then
    return self:remember_failure(key, "empty-bitmap")
  end
  if bitmap.width + self.atlas.padding * 2 > self.atlas.width or bitmap.height + self.atlas.padding * 2 > self.atlas.height then
    return self:remember_failure(key, "bitmap-limit")
  end
  local glyph, reason
  repeat
    if self.atlas:glyph_count() < self.max_entries then
      glyph, reason = self.atlas:try_insert(key, bitmap.width, bitmap.height, bitmap)
    else
      reason = "entry-limit"
    end
    if glyph then break end
  until not self:evict_one()
  if not glyph then
    -- Capacity is temporary. Never put it in the permanent negative cache.
    self.stats.failures = self.stats.failures + 1
    self.stats.capacity_failures = self.stats.capacity_failures + 1
    return nil, reason
  end
  local allocation = glyph.allocation
  for row = 0, allocation.height - 1 do
    ffi.fill(self.pixels + (allocation.y + row) * self.atlas.width + allocation.x, allocation.width)
  end
  if bitmap.width > 0 and bitmap.height > 0 and bitmap.buffer ~= nil then
    for row = 0, bitmap.height - 1 do
      local destination = self.pixels + (glyph.y + row) * self.atlas.width + glyph.x
      ffi.copy(destination, bitmap.buffer + row * bitmap.pitch, bitmap.width)
    end
  end
  glyph.face_id = face.id
  glyph.glyph_id = glyph_id
  glyph.key = key
  glyph.owners = setmetatable({}, { __mode = "k" })
  self.entries[key] = glyph
  self:touch(glyph, owner)
  self.generation = self.generation + 1
  return glyph
end

return GlyphCache
