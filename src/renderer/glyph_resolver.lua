local Errors = require("runtime.errors")

local GlyphResolver = {}
local resolver_mt = {}
resolver_mt.__index = resolver_mt

GlyphResolver.contract = {
  new = "new(font, options?) -> resolver | nil, error",
  resolve = "resolve(text) -> display_text | nil, error",
}

local placeholders = { "□", "?" }

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function positive_integer(value, name)
  if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 1 then
    return config_error(name .. " must be a positive integer", { provided = value })
  end
  return value
end

local function has_glyphs(font, text)
  local font_type = type(font)
  if (font_type ~= "table" and font_type ~= "userdata") or type(font.hasGlyphs) ~= "function" then
    return nil, Errors.new("renderer_resource_error", "renderer font must implement hasGlyphs")
  end
  local ok, present = pcall(font.hasGlyphs, font, text)
  if not ok then
    return nil,
      Errors.new(
        "renderer_resource_error",
        "renderer font glyph lookup failed",
        { cause = present }
      )
  end
  if type(present) ~= "boolean" then
    return nil, Errors.new("renderer_resource_error", "renderer font glyph lookup is invalid")
  end
  return present
end

local function evict(resolver)
  if resolver.entries < resolver.max_entries then
    return
  end
  local oldest_text
  local oldest_used
  for text, entry in pairs(resolver.cache) do
    if oldest_used == nil or entry.used < oldest_used then
      oldest_text = text
      oldest_used = entry.used
    end
  end
  resolver.cache[oldest_text] = nil
  resolver.entries = resolver.entries - 1
end

function GlyphResolver.new(font, options)
  if options == nil then
    options = {}
  end
  if type(options) ~= "table" then
    return config_error("glyph resolver options must be a table")
  end
  for name in pairs(options) do
    if name ~= "max_entries" then
      return config_error("unknown glyph resolver option", { option = name })
    end
  end
  local max_entries, max_entries_error =
    positive_integer(options.max_entries or 4096, "glyph resolver max entries")
  if not max_entries then
    return nil, max_entries_error
  end
  local supported, supported_error = has_glyphs(font, "?")
  if supported == nil then
    return nil, supported_error
  end
  if not supported then
    return nil, Errors.new("renderer_resource_error", "renderer font has no visible fallback glyph")
  end
  return setmetatable({
    cache = {},
    clock = 0,
    entries = 0,
    font = font,
    max_entries = max_entries,
  }, resolver_mt)
end

function resolver_mt:resolve(text)
  if type(text) ~= "string" then
    return config_error("glyph text must be a string")
  end
  local existing = self.cache[text]
  if existing then
    self.clock = self.clock + 1
    existing.used = self.clock
    return existing.display_text
  end
  local display_text = text
  if text ~= "" then
    local supported, supported_error = has_glyphs(self.font, text)
    if supported == nil then
      return nil, supported_error
    end
    if not supported then
      for _, placeholder in ipairs(placeholders) do
        local placeholder_supported, placeholder_error = has_glyphs(self.font, placeholder)
        if placeholder_supported == nil then
          return nil, placeholder_error
        end
        if placeholder_supported then
          display_text = placeholder
          break
        end
      end
    end
  end
  evict(self)
  self.clock = self.clock + 1
  self.cache[text] = { display_text = display_text, used = self.clock }
  self.entries = self.entries + 1
  return display_text
end

return GlyphResolver
