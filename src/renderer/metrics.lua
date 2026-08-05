local Errors = require("runtime.errors")

local Metrics = {}

Metrics.contract = {
  new = "new(font, options?) -> cell_metrics | nil, error",
}

local allowed_options = {
  baseline = true,
  cell_height = true,
  cell_width = true,
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function integer(value, name, minimum)
  if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < minimum then
    return config_error(name .. " must be an integer in range", { provided = value })
  end
  return value
end

local function font_method(font, name, argument)
  local kind = type(font)
  if (kind ~= "table" and kind ~= "userdata") or type(font[name]) ~= "function" then
    return config_error("renderer font must implement " .. name)
  end
  local ok, value = pcall(font[name], font, argument)
  if not ok then
    return nil,
      Errors.new("renderer_resource_error", "renderer font " .. name .. " failed", {
        cause = value,
      })
  end
  if type(value) ~= "number" or value ~= value or value <= 0 then
    return nil,
      Errors.new("renderer_resource_error", "renderer font " .. name .. " is invalid", {
        provided = value,
      })
  end
  return value
end

function Metrics.new(font, options)
  if options == nil then
    options = {}
  end
  if type(options) ~= "table" then
    return config_error("renderer metric options must be a table")
  end
  for name in pairs(options) do
    if not allowed_options[name] then
      return config_error("unknown renderer metric option", { option = name })
    end
  end
  local measured_width, width_error = font_method(font, "getWidth", "M")
  if not measured_width then
    return nil, width_error
  end
  local measured_height, height_error = font_method(font, "getHeight")
  if not measured_height then
    return nil, height_error
  end
  local measured_ascent, ascent_error = font_method(font, "getAscent")
  if not measured_ascent then
    return nil, ascent_error
  end
  local width = options.cell_width or math.ceil(measured_width)
  local valid_width, width_validation_error = integer(width, "renderer cell width", 1)
  if not valid_width then
    return nil, width_validation_error
  end
  local height = options.cell_height or math.ceil(measured_height)
  local valid_height, height_validation_error = integer(height, "renderer cell height", 1)
  if not valid_height then
    return nil, height_validation_error
  end
  local baseline = options.baseline
  if baseline == nil then
    baseline = math.floor(measured_ascent)
  end
  local valid_baseline, baseline_error = integer(baseline, "renderer cell baseline", 0)
  if not valid_baseline then
    return nil, baseline_error
  end
  if valid_baseline > valid_height then
    return config_error("renderer cell baseline must fit within cell height", {
      baseline = valid_baseline,
      cell_height = valid_height,
    })
  end
  return {
    baseline = valid_baseline,
    cell_height = valid_height,
    cell_width = valid_width,
    font = font,
  }
end

return Metrics
