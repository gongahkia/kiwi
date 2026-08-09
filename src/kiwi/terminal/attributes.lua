local bit = require("bit")
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
}

Attributes.default_foreground = Color.pack(0xd8, 0xde, 0xe9, 0xff)
Attributes.default_background = Color.pack(0x20, 0x24, 0x2b, 0xff)

local palette = {
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
    return palette[index + 1]
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

local function resolve_color(color, fallback)
  if color == nil then
    return fallback
  end
  if color.kind == "rgb" then
    return Color.pack(color.red, color.green, color.blue, 0xff)
  end
  return indexed_color(color.index)
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

function Attributes.resolve(value)
  local foreground = resolve_color(value.fg, Attributes.default_foreground)
  local background = resolve_color(value.bg, Attributes.default_background)
  if value.inverse then
    foreground, background = background, foreground
  end
  if value.concealed then
    foreground = background
  end
  local flags = 0
  for name, flag in pairs(Attributes.flags) do
    if value[name] then
      flags = bit.bor(flags, flag)
    end
  end
  return foreground, background, flags
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

return Attributes
