local Errors = require("runtime.errors")
local LoveFont = require("renderer.love_font")

local Renderer = {}
local renderer_mt = {}
renderer_mt.__index = renderer_mt

Renderer.contract = {
  constructor = "new(config) -> renderer | nil, error",
  cell_metrics = "cell_metrics() -> cell_metrics | nil, error",
  draw = "draw(snapshot, damage?) -> nil, error?",
  load_font = "load_font(graphics) -> cell_metrics | nil, error",
  resize = "resize(pixel_width, pixel_height) -> nil, error?",
  destroy = "destroy()",
}

function Renderer.new(config)
  if type(config) ~= "table" then
    return nil, Errors.new("config_error", "renderer config must be a table")
  end
  return setmetatable(
    { config = config, font = nil, metrics = nil, state = "bootstrap" },
    renderer_mt
  )
end

function renderer_mt:load_font(graphics)
  if self.state == "destroyed" then
    return nil, Errors.new("renderer_resource_error", "renderer is destroyed")
  end
  local resource, resource_error = LoveFont.load(graphics, self.config)
  if not resource then
    return nil, resource_error
  end
  self.font = resource.font
  self.metrics = resource.metrics
  return self:cell_metrics()
end

function renderer_mt:cell_metrics()
  if not self.metrics then
    return nil, Errors.new("renderer_resource_error", "renderer font is not loaded")
  end
  return {
    baseline = self.metrics.baseline,
    cell_height = self.metrics.cell_height,
    cell_width = self.metrics.cell_width,
  }
end

function renderer_mt:draw(snapshot, damage)
  if type(snapshot) ~= "table" then
    return nil, Errors.new("config_error", "renderer snapshot must be a table")
  end
  if damage ~= nil and type(damage) ~= "table" then
    return nil, Errors.new("config_error", "renderer damage must be a table")
  end
  return nil, Errors.new("renderer_resource_error", "renderer is not implemented")
end

function renderer_mt:resize(pixel_width, pixel_height)
  if type(pixel_width) ~= "number" or type(pixel_height) ~= "number" then
    return nil, Errors.new("config_error", "renderer dimensions must be numbers")
  end
  return nil, Errors.new("renderer_resource_error", "renderer is not implemented")
end

function renderer_mt:destroy()
  self.state = "destroyed"
end

return Renderer
