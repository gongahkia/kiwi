local Atlas = {}
Atlas.__index = Atlas

function Atlas.new(width, height, padding)
  assert(width > 0 and height > 0, "atlas dimensions must be positive")
  return setmetatable({
    width = width,
    height = height,
    padding = padding or 1,
    cursor_x = 0,
    cursor_y = 0,
    shelf_height = 0,
    used_pixels = 0,
    glyphs = {},
  }, Atlas)
end

function Atlas:insert(key, width, height, bitmap)
  assert(not self.glyphs[key], "glyph already exists in atlas: " .. key)
  assert(width >= 0 and height >= 0, "glyph dimensions must not be negative")
  local padded_width = width + self.padding * 2
  local padded_height = height + self.padding * 2

  if self.cursor_x + padded_width > self.width then
    self.cursor_x = 0
    self.cursor_y = self.cursor_y + self.shelf_height
    self.shelf_height = 0
  end
  if self.cursor_y + padded_height > self.height then
    error("glyph atlas is full while inserting " .. key)
  end

  local glyph = {
    key = key,
    x = self.cursor_x + self.padding,
    y = self.cursor_y + self.padding,
    width = width,
    height = height,
    u0 = (self.cursor_x + self.padding) / self.width,
    v0 = (self.cursor_y + self.padding) / self.height,
    u1 = (self.cursor_x + self.padding + width) / self.width,
    v1 = (self.cursor_y + self.padding + height) / self.height,
    bitmap = bitmap,
  }
  self.glyphs[key] = glyph
  self.cursor_x = self.cursor_x + padded_width
  self.shelf_height = math.max(self.shelf_height, padded_height)
  self.used_pixels = self.used_pixels + width * height
  return glyph
end

function Atlas:get(key)
  return self.glyphs[key]
end

function Atlas:glyph_count()
  local count = 0
  for _ in pairs(self.glyphs) do
    count = count + 1
  end
  return count
end

function Atlas:occupancy()
  return self.used_pixels / (self.width * self.height)
end

return Atlas
