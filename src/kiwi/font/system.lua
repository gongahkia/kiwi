local ffi = require("ffi")
local Face = require("kiwi.font.face")
local GlyphCache = require("kiwi.font.glyph_cache")
local native = require("kiwi.ffi.freetype")
local Resolver = require("kiwi.font.resolver")

local System = {}
System.__index = System

local function sequence_key(codepoints)
  local values = {}
  for index, codepoint in ipairs(codepoints) do values[index] = string.format("%x", codepoint) end
  return table.concat(values, ".")
end

local function face_key(description)
  return description.path .. "#" .. tostring(description.index or 0)
end

function System.new(options)
  options = options or {}
  local library_out = ffi.new("FT_Library[1]")
  if native.lib.FT_Init_FreeType(library_out) ~= 0 then error("FreeType initialization failed") end
  local self = setmetatable({
    library = library_out[0],
    resolver = Resolver.new({ primary_family = options.primary_family }),
    pixel_height = options.pixel_height or 20,
    faces = {},
    face_by_key = {},
    face_cache_limit = options.face_cache_limit or 32,
    next_face_id = 1,
    fallback_cache = {},
    fallback_cache_count = 0,
    fallback_cache_limit = options.fallback_cache_limit or 1024,
    primary_ascii_coverage = {},
    glyph_cache = GlyphCache.new(options.atlas),
    shape_options = {
      ligatures = options.ligatures == true,
      contextual_alternates = options.contextual_alternates == true,
    },
    text_generation = 0,
    stats = {
      primary_hits = 0,
      primary_ascii_cache_hits = 0,
      primary_ascii_coverage_probes = 0,
      fallback_hits = 0,
      fallback_misses = 0,
      negative_fallback_hits = 0,
    },
  }, System)
  local ok, result = xpcall(function()
    local primary = options.font_path and { path = options.font_path, index = 0 } or self.resolver:primary()
    self.primary = assert(self:load_face(primary, true))
    self.metrics = self.primary.metrics
    self.cell_width = self.metrics.cell_width
    self.cell_height = self.metrics.cell_height
    self.font_path = self.primary.path
    self.pixel_height = self.primary.pixel_height
    return self
  end, debug.traceback)
  if not ok then
    self:destroy()
    error(result)
  end
  return result
end

function System:set_shape_options(options)
  options = options or {}
  local ligatures = options.ligatures == true
  local contextual_alternates = options.contextual_alternates == true
  if self.shape_options.ligatures == ligatures and self.shape_options.contextual_alternates == contextual_alternates then return false end
  self.shape_options = { ligatures = ligatures, contextual_alternates = contextual_alternates }
  self.text_generation = self.text_generation + 1
  return true
end

function System:clear_fallback_cache()
  self.fallback_cache = {}
  self.fallback_cache_count = 0
  self.text_generation = self.text_generation + 1
end

function System:load_face(description, required)
  local key = face_key(description)
  local existing = self.face_by_key[key]
  if existing then return existing end
  if #self.faces >= self.face_cache_limit then
    if required then error("font face cache limit reached") end
    return nil, "face-cache-limit"
  end
  local ok, face = xpcall(function()
    return Face.new(self.library, description.path, description.index, self.pixel_height, self.next_face_id)
  end, debug.traceback)
  if not ok then
    if required then error(face) end
    return nil, "font-load-failed"
  end
  self.next_face_id = self.next_face_id + 1
  self.faces[#self.faces + 1] = face
  self.face_by_key[key] = face
  return face
end

function System:face_for_cluster(codepoints)
  local codepoint = codepoints[1]
  local primary_supported
  if #codepoints == 1 and codepoint >= 0x20 and codepoint <= 0x7e then
    primary_supported = self.primary_ascii_coverage[codepoint]
    if primary_supported == nil then
      primary_supported = self.primary:supports(codepoints)
      self.primary_ascii_coverage[codepoint] = primary_supported
      self.stats.primary_ascii_coverage_probes = self.stats.primary_ascii_coverage_probes + 1
    else
      self.stats.primary_ascii_cache_hits = self.stats.primary_ascii_cache_hits + 1
    end
  else
    primary_supported = self.primary:supports(codepoints)
  end
  if primary_supported then
    self.stats.primary_hits = self.stats.primary_hits + 1
    return self.primary, "primary"
  end
  local key = sequence_key(codepoints)
  local cached = self.fallback_cache[key]
  if cached ~= nil then
    if cached == false then
      self.stats.negative_fallback_hits = self.stats.negative_fallback_hits + 1
      return nil, "missing"
    end
    self.stats.fallback_hits = self.stats.fallback_hits + 1
    return cached, "fallback-cache"
  end
  if self.fallback_cache_count >= self.fallback_cache_limit then
    self.stats.fallback_misses = self.stats.fallback_misses + 1
    return nil, "fallback-cache-limit"
  end
  local description = self.resolver:fallback(codepoints)
  local face = description and self:load_face(description, false) or nil
  if face == nil or not face:supports(codepoints) then
    self.fallback_cache[key] = false
    self.fallback_cache_count = self.fallback_cache_count + 1
    self.stats.fallback_misses = self.stats.fallback_misses + 1
    return nil, "missing"
  end
  self.fallback_cache[key] = face
  self.fallback_cache_count = self.fallback_cache_count + 1
  self.stats.fallback_hits = self.stats.fallback_hits + 1
  return face, "fallback"
end

function System:destroy()
  if self.destroyed then return end
  self.destroyed = true
  for index = #(self.faces or {}), 1, -1 do self.faces[index]:destroy() end
  self.faces = {}
  self.face_by_key = {}
  self.glyph_cache = nil
  if self.library ~= nil then native.lib.FT_Done_FreeType(self.library) end
  self.library = nil
end

return System
