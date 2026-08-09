local ffi = require("ffi")
local native = require("kiwi.ffi.freetype")
local Atlas = require("kiwi.font.atlas")

local FreeType = {}

local function require_success(error_code, operation)
  if error_code ~= 0 then
    error(string.format("FreeType %s failed with error %d", operation, error_code))
  end
end

local function find_font()
  local override = os.getenv("KIWI_FONT")
  if override and #override > 0 then
    return override
  end
  local probe = io.popen("fc-match -f '%{file}' 'monospace' 2>/dev/null")
  if probe then
    local candidate = probe:read("*l")
    probe:close()
    if candidate and #candidate > 0 then
      return candidate
    end
  end
  error("No monospace font was found. Set KIWI_FONT to a readable .ttf file.")
end

function FreeType.rasterize(options)
  options = options or {}
  local pixel_height = options.pixel_height or 20
  local atlas_width = options.atlas_width or 1024
  local atlas_height = options.atlas_height or 1024
  local font_path = options.font_path or find_font()
  local library_out = ffi.new("FT_Library[1]")
  require_success(native.lib.FT_Init_FreeType(library_out), "initialization")
  local library = library_out[0]
  local face_out = ffi.new("FT_Face[1]")
  local ok, result = xpcall(function()
    require_success(native.lib.FT_New_Face(library, font_path, 0, face_out), "font loading for " .. font_path)
    local face = face_out[0]
    require_success(native.lib.FT_Set_Pixel_Sizes(face, 0, pixel_height), "pixel-size selection")
    local atlas = Atlas.new(atlas_width, atlas_height, 1)
    local pixels = ffi.new("uint8_t[?]", atlas_width * atlas_height)
    local cell_width = 0

    for codepoint = 32, 126 do
      require_success(native.lib.FT_Load_Char(face, codepoint, native.load_render), "glyph loading for " .. codepoint)
      local slot = face.glyph
      local bitmap = slot.bitmap
      local glyph = atlas:insert(string.char(codepoint), tonumber(bitmap.width), tonumber(bitmap.rows), {
        left = tonumber(slot.bitmap_left),
        top = tonumber(slot.bitmap_top),
        advance = tonumber(slot.advance.x) / 64,
      })
      if codepoint == string.byte("M") then
        cell_width = math.max(1, math.floor(glyph.bitmap.advance + 0.5))
      end
      if bitmap.width > 0 and bitmap.rows > 0 and bitmap.buffer ~= nil then
        local pitch = tonumber(bitmap.pitch)
        assert(pitch > 0, "M0 only supports positive FreeType bitmap pitch")
        for row = 0, tonumber(bitmap.rows) - 1 do
          local destination = pixels + (glyph.y + row) * atlas_width + glyph.x
          ffi.copy(destination, bitmap.buffer + row * pitch, bitmap.width)
        end
      end
    end
    return {
      atlas = atlas,
      pixels = pixels,
      pixel_bytes = atlas_width * atlas_height,
      font_path = font_path,
      pixel_height = pixel_height,
      cell_width = cell_width > 0 and cell_width or math.floor(pixel_height * 0.6),
      cell_height = pixel_height + 4,
    }
  end, debug.traceback)

  if face_out[0] ~= nil then
    native.lib.FT_Done_Face(face_out[0])
  end
  native.lib.FT_Done_FreeType(library)
  if not ok then
    error(result)
  end
  return result
end

return FreeType
