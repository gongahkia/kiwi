-- Cache only font-relative HarfBuzz output. The layout reads these arrays but
-- never publishes or mutates them; screen positions, colours and atlas entries
-- are reconstructed for every damaged row. Face objects (not reusable numeric
-- IDs) and exact UTF-8 text identify an entry. All shaping options invalidate
-- the cache together, including optional script and language overrides.
local Cache = {
  maximum_entries = 256,
  maximum_text_bytes = 32768,
  maximum_glyphs = 4096,
  maximum_run_bytes = 1024,
  maximum_run_glyphs = 256,
}
Cache.__index = Cache

function Cache.new()
  local self = setmetatable({}, Cache)
  self:clear()
  return self
end

function Cache:clear()
  self.faces, self.order = {}, {}
  self.first, self.count, self.text_bytes, self.glyph_count = 1, 0, 0, 0
  self.ligatures, self.contextual_alternates, self.script, self.language = nil, nil, nil, nil
end

function Cache:evict()
  local entry = self.order[self.first]
  local bucket = self.faces[entry.face]
  bucket[entry.text] = nil
  if next(bucket) == nil then self.faces[entry.face] = nil end
  self.order[self.first] = nil
  self.first = self.first % Cache.maximum_entries + 1
  self.count = self.count - 1
  self.text_bytes = self.text_bytes - #entry.text
  self.glyph_count = self.glyph_count - #entry.glyphs
end

-- Returned glyph arrays are borrowed and immutable. Oversized runs are shaped
-- in full but never retained; eviction never alters a previously returned array.
function Cache:shape(face, text, options)
  options = options or {}
  local ligatures, contextual_alternates = not not options.ligatures, not not options.contextual_alternates
  if self.ligatures ~= ligatures or self.contextual_alternates ~= contextual_alternates
      or self.script ~= options.script or self.language ~= options.language then
    self:clear()
    self.ligatures, self.contextual_alternates = ligatures, contextual_alternates
    self.script, self.language = options.script, options.language
  end
  local bucket = self.faces[face]
  local found = bucket and bucket[text]
  if found then return found.glyphs, true end
  local glyphs = face:shape(text, options)
  if #text > Cache.maximum_run_bytes or #glyphs > Cache.maximum_run_glyphs then return glyphs, false end
  while self.count >= Cache.maximum_entries or self.text_bytes + #text > Cache.maximum_text_bytes
      or self.glyph_count + #glyphs > Cache.maximum_glyphs do self:evict() end
  bucket = self.faces[face]
  if not bucket then bucket = {}; self.faces[face] = bucket end
  local entry = { face = face, text = text, glyphs = glyphs }
  bucket[text] = entry
  local slot = (self.first + self.count - 1) % Cache.maximum_entries + 1
  self.order[slot] = entry
  self.count = self.count + 1
  self.text_bytes = self.text_bytes + #text
  self.glyph_count = self.glyph_count + #glyphs
  return glyphs, false
end

return Cache
