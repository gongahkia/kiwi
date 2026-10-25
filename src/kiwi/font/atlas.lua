local Atlas = {}
Atlas.__index = Atlas

function Atlas.new(width, height, padding)
  assert(width > 0 and height > 0, "atlas dimensions must be positive")
  return setmetatable({
    width = width,
    height = height,
    padding = padding or 1,
    root = { x = 0, y = 0, width = width, height = height },
    count = 0,
    used_pixels = 0,
    glyphs = {},
  }, Atlas)
end

-- A guillotine partition keeps live UVs stable. Removing both children merges
-- their parent, so a stream of old glyphs cannot permanently consume the page.
local function allocate(node, width, height)
  if node.first then
    return allocate(node.first, width, height) or allocate(node.second, width, height)
  end
  if node.used or width > node.width or height > node.height then return nil end
  if height < node.height then
    node.first = { x = node.x, y = node.y, width = node.width, height = height, parent = node }
    node.second = { x = node.x, y = node.y + height, width = node.width, height = node.height - height, parent = node }
    return allocate(node.first, width, height)
  end
  if width < node.width then
    node.first = { x = node.x, y = node.y, width = width, height = node.height, parent = node }
    node.second = { x = node.x + width, y = node.y, width = node.width - width, height = node.height, parent = node }
    return allocate(node.first, width, height)
  end
  node.used = true
  return node
end

function Atlas:try_insert(key, width, height, bitmap)
  assert(not self.glyphs[key], "glyph already exists in atlas: " .. key)
  assert(width >= 0 and height >= 0, "glyph dimensions must not be negative")
  local padded_width = width + self.padding * 2
  local padded_height = height + self.padding * 2

  local node = allocate(self.root, padded_width, padded_height)
  if not node then return nil, "atlas-full" end

  local glyph = {
    key = key,
    x = node.x + self.padding,
    y = node.y + self.padding,
    width = width,
    height = height,
    u0 = (node.x + self.padding) / self.width,
    v0 = (node.y + self.padding) / self.height,
    u1 = (node.x + self.padding + width) / self.width,
    v1 = (node.y + self.padding + height) / self.height,
    bitmap = bitmap,
    allocation = node,
  }
  self.glyphs[key] = glyph
  self.count = self.count + 1
  self.used_pixels = self.used_pixels + width * height
  return glyph
end

function Atlas:insert(key, width, height, bitmap)
  return assert(self:try_insert(key, width, height, bitmap), "glyph atlas is full while inserting " .. key)
end

function Atlas:remove(key)
  local glyph = self.glyphs[key]
  if not glyph then return false end
  self.glyphs[key] = nil
  self.count = self.count - 1
  self.used_pixels = self.used_pixels - glyph.width * glyph.height
  local node = glyph.allocation
  node.used = nil
  while node.parent do
    local parent = node.parent
    local first, second = parent.first, parent.second
    if first.used or second.used or first.first or second.first then break end
    parent.first, parent.second = nil, nil
    node = parent
  end
  return true
end

function Atlas:get(key)
  return self.glyphs[key]
end

function Atlas:glyph_count()
  return self.count
end

function Atlas:occupancy()
  return self.used_pixels / (self.width * self.height)
end

return Atlas
