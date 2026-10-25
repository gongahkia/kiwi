local ffi = require("ffi")
local bit = require("bit")
local HarfBuzz = require("kiwi.text.harfbuzz")
local native = require("kiwi.ffi.freetype")

local Face = {}
Face.__index = Face

local function require_success(error_code, operation)
  if error_code ~= 0 then
    error(string.format("FreeType %s failed with error %d", operation, error_code))
  end
end

local function rounded_pixels(value, fallback)
  value = tonumber(value) / 64
  if value <= 0 then return fallback end
  return math.max(1, math.floor(value + 0.5))
end

function Face.new(library, path, index, pixel_height, id, style)
  style = style or {}
  assert(library ~= nil, "FreeType library is required")
  assert(type(path) == "string" and #path > 0, "font face path is required")
  local output = ffi.new("FT_Face[1]")
  require_success(native.lib.FT_New_Face(library, path, index or 0, output), "font loading for " .. path)
  local face = output[0]
  local hb_font
  local ok, result = xpcall(function()
    require_success(native.lib.FT_Set_Pixel_Sizes(face, 0, pixel_height), "pixel-size selection")
    hb_font = HarfBuzz.new_font(face)
    local metrics = face.size.metrics
    require_success(native.lib.FT_Load_Char(face, string.byte("M"), native.load_render), "cell-width measurement")
    local cell_width = math.max(1, math.floor(tonumber(face.glyph.advance.x) / 64 + 0.5))
    return setmetatable({
      native = native,
      library = library,
      face = face,
      hb_font = hb_font,
      id = assert(id, "font face id is required"),
      path = path,
      index = index or 0,
      family = face.family_name ~= nil and ffi.string(face.family_name) or nil,
      bold = bit.band(tonumber(face.style_flags), native.style_bold) ~= 0,
      italic = bit.band(tonumber(face.style_flags), native.style_italic) ~= 0,
      synthetic_bold = style.bold == true and bit.band(tonumber(face.style_flags), native.style_bold) == 0,
      synthetic_italic = style.italic == true and bit.band(tonumber(face.style_flags), native.style_italic) == 0,
      pixel_height = pixel_height,
      metrics = {
        cell_width = cell_width,
        cell_height = rounded_pixels(metrics.height, pixel_height + 4),
        ascent = rounded_pixels(metrics.ascender, pixel_height),
        descent = math.abs(tonumber(metrics.descender) / 64),
        baseline = rounded_pixels(metrics.ascender, pixel_height),
      },
    }, Face)
  end, debug.traceback)
  if not ok then
    HarfBuzz.destroy_font(hb_font)
    native.lib.FT_Done_Face(face)
    error(result)
  end
  return result
end

function Face:glyph_index(codepoint)
  return tonumber(self.native.lib.FT_Get_Char_Index(self.face, codepoint))
end

function Face:supports(codepoints)
  for _, codepoint in ipairs(codepoints) do
    if self:glyph_index(codepoint) == 0 then return false end
  end
  return true
end

function Face:rasterize(glyph_id)
  local synthetic = self.synthetic_bold or self.synthetic_italic
  local flags = self.native.load_color + (synthetic and 0 or self.native.load_render)
  require_success(self.native.lib.FT_Load_Glyph(self.face, glyph_id, flags), "glyph loading for " .. glyph_id)
  local slot = self.face.glyph
  if synthetic then
    if self.synthetic_italic then self.native.lib.FT_GlyphSlot_Oblique(slot) end
    if self.synthetic_bold then self.native.lib.FT_GlyphSlot_Embolden(slot) end
    require_success(self.native.lib.FT_Render_Glyph(slot, self.native.render_normal), "synthetic glyph rendering for " .. glyph_id)
  end
  local bitmap = slot.bitmap
  return {
    width = tonumber(bitmap.width),
    height = tonumber(bitmap.rows),
    pitch = tonumber(bitmap.pitch),
    buffer = bitmap.buffer,
    pixel_mode = tonumber(bitmap.pixel_mode),
    left = tonumber(slot.bitmap_left),
    top = tonumber(slot.bitmap_top),
    advance = tonumber(slot.advance.x) / 64,
  }
end

function Face:shape(text, options)
  return HarfBuzz.shape(self.hb_font, text, options)
end

function Face:destroy()
  if self.destroyed then return end
  self.destroyed = true
  HarfBuzz.destroy_font(self.hb_font)
  self.hb_font = nil
  self.native.lib.FT_Done_Face(self.face)
  self.face = nil
end

return Face
