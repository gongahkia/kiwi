local Errors = require("runtime.errors")

local Rendition = {}

Rendition.contract = {
  copy = "copy(rendition) -> rendition | nil, error",
  new = "new(options?) -> rendition | nil, error",
}

local MAX_U32 = 4294967295

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function byte(value, name)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 255 then
    return config_error(name .. " must be an integer from 0 to 255", { provided = value })
  end
  return value
end

local function has_only(value, allowed, name)
  for field in pairs(value) do
    if not allowed[field] then
      return config_error(name .. " contains an unknown field", { field = field })
    end
  end
  return true
end

local function colour(value, name)
  if value == nil or value == "default" then
    return "default"
  end
  if type(value) ~= "table" then
    return config_error(name .. " must be a colour table or default")
  end
  if value.kind == "indexed" then
    local valid_fields, fields_error = has_only(value, { index = true, kind = true }, name)
    if not valid_fields then
      return nil, fields_error
    end
    local index, index_error = byte(value.index, name .. ".index")
    if not index then
      return nil, index_error
    end
    return { index = index, kind = "indexed" }
  end
  if value.kind == "rgb" then
    local valid_fields, fields_error =
      has_only(value, { blue = true, green = true, kind = true, red = true }, name)
    if not valid_fields then
      return nil, fields_error
    end
    local red, red_error = byte(value.red, name .. ".red")
    if not red then
      return nil, red_error
    end
    local green, green_error = byte(value.green, name .. ".green")
    if not green then
      return nil, green_error
    end
    local blue, blue_error = byte(value.blue, name .. ".blue")
    if not blue then
      return nil, blue_error
    end
    return { blue = blue, green = green, kind = "rgb", red = red }
  end
  return config_error(name .. " has an unsupported colour kind", { provided = value.kind })
end

local function attributes(value)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > MAX_U32 then
    return config_error("attributes must be an unsigned 32-bit integer", { provided = value })
  end
  return value
end

function Rendition.new(options)
  if options == nil then
    options = {}
  end
  if type(options) ~= "table" then
    return config_error("rendition options must be a table")
  end
  for name in pairs(options) do
    if name ~= "attributes" and name ~= "background" and name ~= "foreground" then
      return config_error("unknown rendition option", { option = name })
    end
  end
  local requested_attributes = options.attributes
  if requested_attributes == nil then
    requested_attributes = 0
  end
  local validated_attributes, attributes_error = attributes(requested_attributes)
  if not validated_attributes then
    return nil, attributes_error
  end
  local foreground, foreground_error = colour(options.foreground, "foreground")
  if not foreground then
    return nil, foreground_error
  end
  local background, background_error = colour(options.background, "background")
  if not background then
    return nil, background_error
  end
  return {
    attributes = validated_attributes,
    background = background,
    foreground = foreground,
  }
end

function Rendition.copy(rendition)
  return Rendition.new(rendition)
end

return Rendition
