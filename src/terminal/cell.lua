local Errors = require("runtime.errors")

local Cell = {}

Cell.contract = {
  new = "new(options?) -> cell | nil, error",
}

local MAX_U32 = 4294967295

local allowed_options = {
  attributes = true,
  background = true,
  continuation = true,
  foreground = true,
  hyperlink_id = true,
  text = true,
  width = true,
}

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
    return { kind = "indexed", index = index }
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

function Cell.new(options)
  if options == nil then
    options = {}
  end
  if type(options) ~= "table" then
    return config_error("cell options must be a table")
  end
  for name in pairs(options) do
    if not allowed_options[name] then
      return config_error("unknown cell option", { option = name })
    end
  end

  local text = options.text
  if text == nil then
    text = ""
  end
  if type(text) ~= "string" then
    return config_error("cell text must be a string")
  end
  local width = options.width
  if width == nil then
    width = 1
  end
  if width ~= 0 and width ~= 1 and width ~= 2 then
    return config_error("cell width must be 0, 1, or 2", { provided = width })
  end
  local continuation = options.continuation
  if continuation == nil then
    continuation = false
  end
  if type(continuation) ~= "boolean" then
    return config_error("cell continuation must be a boolean")
  end
  if continuation ~= (width == 0) then
    return config_error("cell width and continuation disagree")
  end
  if continuation and text ~= "" then
    return config_error("continuation cells cannot contain text")
  end

  local rendition_attributes = options.attributes
  if rendition_attributes == nil then
    rendition_attributes = 0
  end
  local validated_attributes, attributes_error = attributes(rendition_attributes)
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
  if options.hyperlink_id ~= nil then
    return config_error("hyperlink_id is not supported by this compatibility profile")
  end

  return {
    attributes = validated_attributes,
    background = background,
    continuation = continuation,
    foreground = foreground,
    hyperlink_id = nil,
    text = text,
    width = width,
  }
end

return Cell
