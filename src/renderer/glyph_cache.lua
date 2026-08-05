local Errors = require("runtime.errors")

local GlyphCache = {}
local cache_mt = {}
cache_mt.__index = cache_mt

GlyphCache.contract = {
  constructor = "new(font, metrics, config?) -> glyph_cache | nil, error",
  get = "get(text, style?) -> glyph | nil, error",
  stats = "stats() -> glyph_cache_stats",
}

local allowed_styles = { bold = true, regular = true }

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function positive_integer(value, name)
  if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 1 then
    return config_error(name .. " must be a positive integer", { provided = value })
  end
  return value
end

local function nonnegative_integer(value, name)
  if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 0 then
    return config_error(name .. " must be a non-negative integer", { provided = value })
  end
  return value
end

local function valid_font(font)
  local kind = type(font)
  if (kind ~= "table" and kind ~= "userdata") or type(font.getWidth) ~= "function" then
    return config_error("renderer glyph font must implement getWidth")
  end
  return font
end

local function valid_metrics(metrics)
  if type(metrics) ~= "table" then
    return config_error("renderer glyph metrics must be a table")
  end
  for _, name in ipairs({ "cell_height", "cell_width" }) do
    local value, value_error = positive_integer(metrics[name], "renderer glyph metric " .. name)
    if not value then
      return nil, value_error
    end
  end
  local baseline, baseline_error =
    nonnegative_integer(metrics.baseline, "renderer glyph metric baseline")
  if not baseline then
    return nil, baseline_error
  end
  return metrics
end

local function glyph_key(text, style)
  return style .. "\0" .. text
end

local function copy_glyph(glyph)
  return {
    advance = glyph.advance,
    style = glyph.style,
    text = glyph.text,
  }
end

function GlyphCache.new(font, metrics, config)
  local valid_font_value, font_error = valid_font(font)
  if not valid_font_value then
    return nil, font_error
  end
  local valid_metrics_value, metrics_error = valid_metrics(metrics)
  if not valid_metrics_value then
    return nil, metrics_error
  end
  if config == nil then
    config = {}
  end
  if type(config) ~= "table" then
    return config_error("renderer glyph cache config must be a table")
  end
  for name in pairs(config) do
    if name ~= "max_entries" then
      return config_error("unknown renderer glyph cache option", { option = name })
    end
  end
  local max_entries, max_entries_error =
    positive_integer(config.max_entries or 4096, "renderer glyph cache maximum entries")
  if not max_entries then
    return nil, max_entries_error
  end
  return setmetatable({
    entries = {},
    font = valid_font_value,
    hits = 0,
    max_entries = max_entries,
    metrics = valid_metrics_value,
    misses = 0,
    sequence = 0,
    size = 0,
  }, cache_mt)
end

local function evict(cache)
  if cache.size < cache.max_entries then
    return true
  end
  local oldest_key
  local oldest_used
  for key, entry in pairs(cache.entries) do
    if oldest_used == nil or entry.used < oldest_used then
      oldest_key = key
      oldest_used = entry.used
    end
  end
  if oldest_key == nil then
    return nil, Errors.new("internal_invariant_error", "renderer glyph cache size is inconsistent")
  end
  cache.entries[oldest_key] = nil
  cache.size = cache.size - 1
  return true
end

function cache_mt:get(text, style)
  if type(text) ~= "string" or text == "" then
    return config_error("renderer glyph text must be non-empty bytes", { provided = text })
  end
  local selected_style = style or "regular"
  if not allowed_styles[selected_style] then
    return config_error("renderer glyph style is unsupported", { provided = style })
  end
  local key = glyph_key(text, selected_style)
  self.sequence = self.sequence + 1
  local cached = self.entries[key]
  if cached then
    cached.used = self.sequence
    self.hits = self.hits + 1
    return copy_glyph(cached)
  end
  local ok, measured = pcall(self.font.getWidth, self.font, text)
  if not ok then
    return nil,
      Errors.new("renderer_resource_error", "renderer glyph measurement failed", {
        cause = measured,
      })
  end
  if type(measured) ~= "number" or measured ~= measured or measured < 0 then
    return nil,
      Errors.new("renderer_resource_error", "renderer glyph measurement is invalid", {
        provided = measured,
      })
  end
  local evicted, eviction_error = evict(self)
  if not evicted then
    return nil, eviction_error
  end
  local glyph = {
    advance = math.ceil(measured),
    style = selected_style,
    text = text,
    used = self.sequence,
  }
  self.entries[key] = glyph
  self.misses = self.misses + 1
  self.size = self.size + 1
  return copy_glyph(glyph)
end

function cache_mt:stats()
  return {
    entries = self.size,
    hits = self.hits,
    max_entries = self.max_entries,
    misses = self.misses,
  }
end

return GlyphCache
