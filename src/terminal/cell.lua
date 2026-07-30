local Errors = require("runtime.errors")
local Rendition = require("terminal.rendition")

local Cell = {}

Cell.contract = {
  new = "new(options?) -> cell | nil, error",
}

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

  local rendition, rendition_error = Rendition.new({
    attributes = options.attributes,
    background = options.background,
    foreground = options.foreground,
  })
  if not rendition then
    return nil, rendition_error
  end
  if options.hyperlink_id ~= nil then
    return config_error("hyperlink_id is not supported by this compatibility profile")
  end

  return {
    attributes = rendition.attributes,
    background = rendition.background,
    continuation = continuation,
    foreground = rendition.foreground,
    hyperlink_id = nil,
    text = text,
    width = width,
  }
end

return Cell
