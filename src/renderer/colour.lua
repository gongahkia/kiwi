local Errors = require("runtime.errors")

local Colour = {}

Colour.default_background = { blue = 24, green = 20, red = 16 }
Colour.default_foreground = { blue = 216, green = 219, red = 224 }

local ansi = {
  { blue = 0, green = 0, red = 0 },
  { blue = 0, green = 0, red = 205 },
  { blue = 0, green = 205, red = 0 },
  { blue = 0, green = 205, red = 205 },
  { blue = 238, green = 0, red = 0 },
  { blue = 205, green = 0, red = 205 },
  { blue = 205, green = 205, red = 0 },
  { blue = 229, green = 229, red = 229 },
  { blue = 127, green = 127, red = 127 },
  { blue = 255, green = 0, red = 0 },
  { blue = 0, green = 255, red = 0 },
  { blue = 0, green = 255, red = 255 },
  { blue = 255, green = 92, red = 92 },
  { blue = 255, green = 0, red = 255 },
  { blue = 255, green = 255, red = 0 },
  { blue = 255, green = 255, red = 255 },
}

Colour.contract = {
  resolve = "resolve(terminal_colour, fallback) -> rgb | nil, error",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function rgb(red, green, blue)
  return { blue = blue / 255, green = green / 255, red = red / 255 }
end

local function valid_byte(value)
  return type(value) == "number" and value % 1 == 0 and value >= 0 and value <= 255
end

local function fallback_colour(value)
  if
    type(value) ~= "table"
    or not valid_byte(value.red)
    or not valid_byte(value.green)
    or not valid_byte(value.blue)
  then
    return config_error("renderer fallback colour is invalid")
  end
  return value
end

function Colour.resolve(value, fallback)
  local fallback_value, fallback_error = fallback_colour(fallback)
  if not fallback_value then
    return nil, fallback_error
  end
  if value == "default" then
    return rgb(fallback_value.red, fallback_value.green, fallback_value.blue)
  end
  if type(value) ~= "table" then
    return config_error("renderer terminal colour is invalid")
  end
  if
    value.kind == "rgb"
    and valid_byte(value.red)
    and valid_byte(value.green)
    and valid_byte(value.blue)
  then
    return rgb(value.red, value.green, value.blue)
  end
  if value.kind ~= "indexed" or not valid_byte(value.index) then
    return config_error("renderer terminal colour is invalid")
  end
  if value.index < 16 then
    local selected = ansi[value.index + 1]
    return rgb(selected.red, selected.green, selected.blue)
  end
  if value.index < 232 then
    local cube = value.index - 16
    local values = { 0, 95, 135, 175, 215, 255 }
    local red = values[math.floor(cube / 36) + 1]
    local green = values[math.floor(cube / 6) % 6 + 1]
    local blue = values[cube % 6 + 1]
    return rgb(red, green, blue)
  end
  local shade = 8 + (value.index - 232) * 10
  return rgb(shade, shade, shade)
end

return Colour
