local Errors = require("runtime.errors")

local Renderer = {}
local renderer_mt = {}
renderer_mt.__index = renderer_mt

Renderer.contract = {
  constructor = "new(config) -> renderer | nil, error",
  draw = "draw(snapshot, damage?) -> nil, error?",
  resize = "resize(pixel_width, pixel_height) -> nil, error?",
  destroy = "destroy()",
}

function Renderer.new(config)
  if type(config) ~= "table" then
    return nil, Errors.new("config_error", "renderer config must be a table")
  end
  return setmetatable({ config = config, state = "bootstrap" }, renderer_mt)
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
