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
    max_bitmap_dimension = options.max_bitmap_dimension or 512,
    entries = {},
    generation = 0,
    stats = { hits = 0, misses = 0, failures = 0, color_unsupported = 0 },
  }, GlyphCache)
end

function GlyphCache:get_or_insert(face, glyph_id)
  if glyph_id == 0 then
    self.stats.failures = self.stats.failures + 1
    return nil, "missing-glyph"
  end
  local key = key_for(face, glyph_id)
  local existing = self.entries[key]
  if existing then
    self.stats.hits = self.stats.hits + 1
    return existing
  end
  self.stats.misses = self.stats.misses + 1
  if self.atlas:glyph_count() >= self.max_entries then
    self.stats.failures = self.stats.failures + 1
    return nil, "entry-limit"
  end
  local bitmap = face:rasterize(glyph_id)
  if bitmap.pixel_mode ~= face.native.pixel_mode_gray then
    if bitmap.pixel_mode == face.native.pixel_mode_bgra then self.stats.color_unsupported = self.stats.color_unsupported + 1 end
    self.stats.failures = self.stats.failures + 1
    return nil, "unsupported-pixel-mode"
  end
  if bitmap.width > self.max_bitmap_dimension or bitmap.height > self.max_bitmap_dimension or bitmap.pitch <= 0 then
    self.stats.failures = self.stats.failures + 1
    return nil, "bitmap-limit"
  end
  if bitmap.width == 0 or bitmap.height == 0 then
    self.stats.failures = self.stats.failures + 1
    return nil, "empty-bitmap"
  end
  local ok, glyph = pcall(self.atlas.insert, self.atlas, key, bitmap.width, bitmap.height, bitmap)
  if not ok then
    self.stats.failures = self.stats.failures + 1
    return nil, "atlas-full"
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
  self.entries[key] = glyph
  self.generation = self.generation + 1
  return glyph
end

return GlyphCache
