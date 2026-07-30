local Errors = require("runtime.errors")
local Metrics = require("renderer.metrics")

local LoveFont = {}

LoveFont.contract = {
  load = "load(graphics, options?) -> font_resource | nil, error",
}

local allowed_options = {
  baseline = true,
  cell_height = true,
  cell_width = true,
  cursor_style = true,
  font_path = true,
  font_size = true,
  max_glyph_entries = true,
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function font_size(value)
  if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 1 then
    return config_error("renderer font size must be a positive integer", { provided = value })
  end
  return value
end

function LoveFont.load(graphics, options)
  if options == nil then
    options = {}
  end
  if type(graphics) ~= "table" or type(graphics.newFont) ~= "function" then
    return config_error("renderer graphics must implement newFont")
  end
  if type(options) ~= "table" then
    return config_error("renderer font options must be a table")
  end
  for name in pairs(options) do
    if not allowed_options[name] then
      return config_error("unknown renderer font option", { option = name })
    end
  end
  if options.font_path ~= nil and type(options.font_path) ~= "string" then
    return config_error("renderer font path must be a string", { provided = options.font_path })
  end
  local size, size_error = font_size(options.font_size or 14)
  if not size then
    return nil, size_error
  end
  local ok, font, detail
  if options.font_path then
    ok, font, detail = pcall(graphics.newFont, options.font_path, size)
  else
    ok, font, detail = pcall(graphics.newFont, size)
  end
  if not ok then
    return nil, Errors.new("renderer_resource_error", "renderer font load failed", { cause = font })
  end
  if not font then
    return nil,
      Errors.new("renderer_resource_error", "renderer font load failed", { cause = detail })
  end
  local metrics, metrics_error = Metrics.new(font, {
    baseline = options.baseline,
    cell_height = options.cell_height,
    cell_width = options.cell_width,
  })
  if not metrics then
    return nil, metrics_error
  end
  return { font = font, metrics = metrics }
end

return LoveFont
