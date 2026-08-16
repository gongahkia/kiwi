local Color = require("kiwi.renderer.color")

local Attributes = {}

Attributes.flags = {
  bold = 0x01,
  semantic = 0x02,
  recent = 0x04,
  faint = 0x08,
  italic = 0x10,
  underline = 0x20,
  inverse = 0x40,
  concealed = 0x80,
  strike = 0x100,
  hyperlink = 0x200,
}

Attributes.default_foreground = Color.pack(0xd8, 0xde, 0xe9, 0xff)
Attributes.default_background = Color.pack(0x20, 0x24, 0x2b, 0xff)

local standard_palette = {
  Color.pack(0x3b, 0x42, 0x52, 0xff), Color.pack(0xbf, 0x61, 0x6a, 0xff),
  Color.pack(0xa3, 0xbe, 0x8c, 0xff), Color.pack(0xeb, 0xcb, 0x8b, 0xff),
  Color.pack(0x81, 0xa1, 0xc1, 0xff), Color.pack(0xb4, 0x8e, 0xad, 0xff),
  Color.pack(0x88, 0xc0, 0xd0, 0xff), Color.pack(0xe5, 0xe9, 0xf0, 0xff),
  Color.pack(0x4c, 0x56, 0x6a, 0xff), Color.pack(0xbf, 0x61, 0x6a, 0xff),
  Color.pack(0xa3, 0xbe, 0x8c, 0xff), Color.pack(0xeb, 0xcb, 0x8b, 0xff),
  Color.pack(0x81, 0xa1, 0xc1, 0xff), Color.pack(0xb4, 0x8e, 0xad, 0xff),
  Color.pack(0x8f, 0xbc, 0xbb, 0xff), Color.pack(0xec, 0xef, 0xf4, 0xff),
}

local function indexed_color(index)
  if index < 16 then
    return standard_palette[index + 1]
  end
  if index >= 232 then
    local grey = 8 + (index - 232) * 10
    return Color.pack(grey, grey, grey, 0xff)
  end
  local value = index - 16
  local scale = { 0, 95, 135, 175, 215, 255 }
  local red = math.floor(value / 36)
  local green = math.floor(value / 6) % 6
  local blue = value % 6
  return Color.pack(scale[red + 1], scale[green + 1], scale[blue + 1], 0xff)
end

local Palette = {}
Palette.__index = Palette

function Palette.new(options)
  options = options or {}
  local self = setmetatable({
    foreground = options.foreground or Attributes.default_foreground,
    background = options.background or Attributes.default_background,
    indexed_overrides = {},
  }, Palette)
  assert(type(self.foreground) == "number" and type(self.background) == "number", "terminal default colours must be packed RGBA values")
  return self
end

function Palette:indexed(index)
  assert(type(index) == "number" and index >= 0 and index <= 255 and index % 1 == 0, "terminal palette index must be an integer from 0 through 255")
  return self.indexed_overrides[index] or indexed_color(index)
end

function Palette:set_indexed(index, value)
  assert(type(value) == "number", "terminal palette colour must be a packed RGBA value")
  self:indexed(index)
  self.indexed_overrides[index] = value
end

function Palette:reset_indexed(index)
  if index == nil then
    self.indexed_overrides = {}
    return
  end
  self:indexed(index)
  self.indexed_overrides[index] = nil
end

function Palette:set_default(channel, value)
  assert(channel == "foreground" or channel == "background", "terminal palette default channel is invalid")
  assert(type(value) == "number", "terminal default colour must be a packed RGBA value")
  self[channel] = value
end

function Palette:reset_default(channel)
  assert(channel == "foreground" or channel == "background", "terminal palette default channel is invalid")
  self[channel] = channel == "foreground" and Attributes.default_foreground or Attributes.default_background
end

function Palette:resolve_color(color, channel)
  if color == nil then
    return channel == "foreground" and self.foreground or self.background, 0
  end
  if color.kind == "rgb" then
    return Color.pack(color.red, color.green, color.blue, 0xff), nil
  end
  return self:indexed(color.index), color.index + 1
end

function Attributes.default()
  return {
    fg = nil,
    bg = nil,
    bold = false,
    faint = false,
    italic = false,
    underline = false,
    inverse = false,
    concealed = false,
    strike = false,
  }
end

function Attributes.copy(value)
  local copy = {}
  for key, item in pairs(value) do
    if type(item) == "table" then
      local item_copy = {}
      for item_key, item_value in pairs(item) do
        item_copy[item_key] = item_value
      end
      copy[key] = item_copy
    else
      copy[key] = item
    end
  end
  return copy
end

function Attributes.resolve(value, palette)
  palette = palette or Attributes.default_palette
  local foreground, foreground_slot = palette:resolve_color(value.fg, "foreground")
  local background, background_slot = palette:resolve_color(value.bg, "background")
  if value.inverse then
    foreground, background = background, foreground
    foreground_slot, background_slot = background_slot, foreground_slot
  end
  if value.concealed then
    foreground = background
    foreground_slot = background_slot
  end
  local flags = 0
  if value.bold then flags = flags + Attributes.flags.bold end
  if value.semantic then flags = flags + Attributes.flags.semantic end
  if value.recent then flags = flags + Attributes.flags.recent end
  if value.faint then flags = flags + Attributes.flags.faint end
  if value.italic then flags = flags + Attributes.flags.italic end
  if value.underline then flags = flags + Attributes.flags.underline end
  if value.inverse then flags = flags + Attributes.flags.inverse end
  if value.concealed then flags = flags + Attributes.flags.concealed end
  if value.strike then flags = flags + Attributes.flags.strike end
  return foreground, background, flags, foreground_slot, background_slot
end

function Attributes.apply_sgr(current, parameters)
  if #parameters == 0 then
    parameters = { 0 }
  end
  local index = 1
  while index <= #parameters do
    local parameter = parameters[index] or 0
    if parameter == 0 then
      current = Attributes.default()
    elseif parameter == 1 then
      current.bold = true
    elseif parameter == 2 then
      current.faint = true
    elseif parameter == 3 then
      current.italic = true
    elseif parameter == 4 or parameter == 21 then
      current.underline = true
    elseif parameter == 7 then
      current.inverse = true
    elseif parameter == 8 then
      current.concealed = true
    elseif parameter == 9 then
      current.strike = true
    elseif parameter == 22 then
      current.bold = false
      current.faint = false
    elseif parameter == 23 then
      current.italic = false
    elseif parameter == 24 then
      current.underline = false
    elseif parameter == 27 then
      current.inverse = false
    elseif parameter == 28 then
      current.concealed = false
    elseif parameter == 29 then
      current.strike = false
    elseif parameter >= 30 and parameter <= 37 then
      current.fg = { kind = "indexed", index = parameter - 30 }
    elseif parameter >= 40 and parameter <= 47 then
      current.bg = { kind = "indexed", index = parameter - 40 }
    elseif parameter >= 90 and parameter <= 97 then
      current.fg = { kind = "indexed", index = parameter - 90 + 8 }
    elseif parameter >= 100 and parameter <= 107 then
      current.bg = { kind = "indexed", index = parameter - 100 + 8 }
    elseif parameter == 39 then
      current.fg = nil
    elseif parameter == 49 then
      current.bg = nil
    elseif parameter == 38 or parameter == 48 then
      local target = parameter == 38 and "fg" or "bg"
      local mode = parameters[index + 1]
      if mode == 5 and parameters[index + 2] and parameters[index + 2] >= 0 and parameters[index + 2] <= 255 then
        current[target] = { kind = "indexed", index = parameters[index + 2] }
        index = index + 2
      elseif mode == 2 and parameters[index + 4] and parameters[index + 2] >= 0 and parameters[index + 2] <= 255 and parameters[index + 3] >= 0 and parameters[index + 3] <= 255 and parameters[index + 4] >= 0 and parameters[index + 4] <= 255 then
        current[target] = { kind = "rgb", red = parameters[index + 2], green = parameters[index + 3], blue = parameters[index + 4] }
        index = index + 4
      end
    end
    index = index + 1
  end
  return current
end

Attributes.Palette = Palette
Attributes.default_palette = Palette.new()

return Attributes
