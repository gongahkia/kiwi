local Errors = require("runtime.errors")

local Dpi = {}

Dpi.contract = {
  dimensions = "dimensions(graphics) -> dimensions | nil, error",
}

local MAX_U32 = 4294967295

local function resource_error(message, detail)
  return nil, Errors.new("renderer_resource_error", message, detail)
end

local function uint32(value, name)
  if
    type(value) ~= "number"
    or value ~= value
    or value % 1 ~= 0
    or value < 0
    or value > MAX_U32
  then
    return resource_error(name .. " must be an unsigned 32-bit integer", { provided = value })
  end
  return value
end

local function scale(value)
  if type(value) ~= "number" or value ~= value or value <= 0 then
    return resource_error("renderer DPI scale must be positive", { provided = value })
  end
  return value
end

local function method(graphics, name)
  if type(graphics) ~= "table" or type(graphics[name]) ~= "function" then
    return resource_error("renderer graphics must implement " .. name)
  end
  return graphics[name]
end

local function call(graphics, name)
  local callback, callback_error = method(graphics, name)
  if not callback then
    return nil, nil, callback_error
  end
  local ok, first, second = pcall(callback)
  if not ok then
    return nil, nil, resource_error("renderer graphics " .. name .. " failed", { cause = first })
  end
  return first, second
end

function Dpi.dimensions(graphics)
  local width, height, dimensions_error = call(graphics, "getDimensions")
  if not width then
    return nil, dimensions_error
  end
  local valid_width, width_error = uint32(width, "renderer window width")
  if not valid_width then
    return nil, width_error
  end
  local valid_height, height_error = uint32(height, "renderer window height")
  if not valid_height then
    return nil, height_error
  end
  local pixel_width, pixel_height, pixels_error = call(graphics, "getPixelDimensions")
  if not pixel_width then
    return nil, pixels_error
  end
  local valid_pixel_width, pixel_width_error = uint32(pixel_width, "renderer pixel width")
  if not valid_pixel_width then
    return nil, pixel_width_error
  end
  local valid_pixel_height, pixel_height_error = uint32(pixel_height, "renderer pixel height")
  if not valid_pixel_height then
    return nil, pixel_height_error
  end
  local dpi_scale, dpi_scale_error = call(graphics, "getDPIScale")
  if not dpi_scale then
    return nil, dpi_scale_error
  end
  local valid_scale, scale_error = scale(dpi_scale)
  if not valid_scale then
    return nil, scale_error
  end
  return {
    dpi_scale = valid_scale,
    pixel_height = valid_pixel_height,
    pixel_width = valid_pixel_width,
    window_height = valid_height,
    window_width = valid_width,
  }
end

return Dpi
