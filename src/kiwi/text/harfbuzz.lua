local native = require("kiwi.ffi.harfbuzz")

local HarfBuzz = {
  cluster_level = "monotone-graphemes",
}

local function assert_handle(handle, name)
  if handle == nil then error("HarfBuzz " .. name .. " returned a null handle") end
  return handle
end

local function tag(value)
  assert(#value == 4, "OpenType feature tag must contain four bytes")
  return value:byte(1) * 0x1000000 + value:byte(2) * 0x10000 + value:byte(3) * 0x100 + value:byte(4)
end

local function feature_list(options)
  if options == nil then return nil, 0 end
  local features = native.ffi.new("hb_feature_t[2]")
  features[0].tag = tag("liga")
  features[0].value = options.ligatures and 1 or 0
  features[0].start = 0
  features[0]["end"] = native.feature_global_end
  features[1].tag = tag("calt")
  features[1].value = options.contextual_alternates and 1 or 0
  features[1].start = 0
  features[1]["end"] = native.feature_global_end
  return features, 2
end

function HarfBuzz.version()
  return native.ffi.string(native.lib.hb_version_string())
end

function HarfBuzz.new_font(face)
  return assert_handle(native.lib.hb_ft_font_create_referenced(face), "font creation")
end

function HarfBuzz.destroy_font(font)
  if font ~= nil then native.lib.hb_font_destroy(font) end
end

function HarfBuzz.shape(font, text, options)
  assert(font ~= nil, "HarfBuzz shape needs a font")
  assert(type(text) == "string", "HarfBuzz shape needs UTF-8 text")
  options = options or {}
  local buffer = assert_handle(native.lib.hb_buffer_create(), "buffer creation")
  local ok, result = xpcall(function()
    native.lib.hb_buffer_set_cluster_level(buffer, native.cluster_level_monotone_graphemes)
    native.lib.hb_buffer_add_utf8(buffer, text, #text, 0, #text)
    native.lib.hb_buffer_guess_segment_properties(buffer)
    native.lib.hb_buffer_set_direction(buffer, native.direction_ltr)
    if options.script then
      native.lib.hb_buffer_set_script(buffer, native.lib.hb_script_from_string(options.script, #options.script))
    end
    if options.language then
      native.lib.hb_buffer_set_language(buffer, native.lib.hb_language_from_string(options.language, #options.language))
    end
    local features, feature_count = feature_list(options)
    native.lib.hb_shape(font, buffer, features, feature_count)
    local length = native.ffi.new("unsigned int[1]")
    local infos = native.lib.hb_buffer_get_glyph_infos(buffer, length)
    local positions = native.lib.hb_buffer_get_glyph_positions(buffer, length)
    local glyphs = {}
    for index = 0, tonumber(length[0]) - 1 do
      glyphs[#glyphs + 1] = {
        glyph_id = tonumber(infos[index].codepoint),
        cluster = tonumber(infos[index].cluster),
        x_advance = tonumber(positions[index].x_advance),
        y_advance = tonumber(positions[index].y_advance),
        x_offset = tonumber(positions[index].x_offset),
        y_offset = tonumber(positions[index].y_offset),
      }
    end
    return glyphs
  end, debug.traceback)
  native.lib.hb_buffer_destroy(buffer)
  if not ok then error(result) end
  return result
end

return HarfBuzz
