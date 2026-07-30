local Errors = require("runtime.errors")

local Grid = {}

Grid.contract = {
  layout = "layout(metrics, window_width, window_height, options?) -> layout | nil, error",
}

local MAX_U32 = 4294967295

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function uint32(value, name)
  if
    type(value) ~= "number"
    or value ~= value
    or value % 1 ~= 0
    or value < 0
    or value > MAX_U32
  then
    return config_error(name .. " must be an unsigned 32-bit integer", { provided = value })
  end
  return value
end

local function positive_uint32(value, name)
  local valid, valid_error = uint32(value, name)
  if not valid or valid == 0 then
    return nil, valid_error or Errors.new("config_error", name .. " must be positive")
  end
  return valid
end

local function metrics_dimensions(metrics)
  if type(metrics) ~= "table" then
    return config_error("renderer metrics must be a table")
  end
  local cell_width, cell_width_error = positive_uint32(metrics.cell_width, "renderer cell width")
  if not cell_width then
    return nil, nil, cell_width_error
  end
  local cell_height, cell_height_error =
    positive_uint32(metrics.cell_height, "renderer cell height")
  if not cell_height then
    return nil, nil, cell_height_error
  end
  return cell_width, cell_height
end

function Grid.layout(metrics, window_width, window_height, options)
  if options == nil then
    options = {}
  end
  if type(options) ~= "table" then
    return config_error("renderer grid options must be a table")
  end
  for name in pairs(options) do
    if name ~= "padding" then
      return config_error("unknown renderer grid option", { option = name })
    end
  end
  local cell_width, cell_height, metrics_error = metrics_dimensions(metrics)
  if not cell_width then
    return nil, metrics_error
  end
  local width, width_error = uint32(window_width, "renderer window width")
  if not width then
    return nil, width_error
  end
  local height, height_error = uint32(window_height, "renderer window height")
  if not height then
    return nil, height_error
  end
  local padding, padding_error = uint32(options.padding or 0, "renderer grid padding")
  if not padding then
    return nil, padding_error
  end
  local available_width = math.max(1, width - padding * 2)
  local available_height = math.max(1, height - padding * 2)
  local columns = math.max(1, math.floor(available_width / cell_width))
  local rows = math.max(1, math.floor(available_height / cell_height))
  local grid_width = columns * cell_width
  local grid_height = rows * cell_height
  return {
    cell_height = cell_height,
    cell_width = cell_width,
    columns = columns,
    grid_height = grid_height,
    grid_width = grid_width,
    padding = padding,
    x = math.floor((width - grid_width) / 2),
    y = math.floor((height - grid_height) / 2),
    rows = rows,
    window_height = height,
    window_width = width,
  }
end

return Grid
