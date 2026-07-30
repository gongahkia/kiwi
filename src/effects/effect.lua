local Errors = require("runtime.errors")

local Effect = {}
local effect_mt = {}
effect_mt.__index = effect_mt

Effect.contract = {
  constructor = "new(manifest) -> effect | nil, error",
  on_event = "on_event(event) -> nil, error?",
  update = "update(visual_time_us) -> nil, error?",
  transform_cell = "transform_cell(visual_cell) -> nil, error?",
  destroy = "destroy()",
}

function Effect.new(manifest)
  if type(manifest) ~= "table" or type(manifest.id) ~= "string" or manifest.id == "" then
    return nil, Errors.new("effect_load_error", "effect manifest requires a non-empty id")
  end
  return setmetatable({ manifest = manifest, state = "bootstrap" }, effect_mt)
end

function effect_mt:on_event(event)
  if type(event) ~= "table" then
    return nil, Errors.new("effect_runtime_error", "effect event must be a table")
  end
  return nil, Errors.new("effect_runtime_error", "effect event hook is not implemented")
end

function effect_mt:update(visual_time_us)
  if type(visual_time_us) ~= "number" then
    return nil, Errors.new("effect_runtime_error", "effect visual time must be a number")
  end
  return nil, Errors.new("effect_runtime_error", "effect update hook is not implemented")
end

function effect_mt:transform_cell(visual_cell)
  if type(visual_cell) ~= "table" then
    return nil, Errors.new("effect_runtime_error", "visual cell must be a table")
  end
  return nil, Errors.new("effect_runtime_error", "effect transform hook is not implemented")
end

function effect_mt:destroy()
  self.state = "destroyed"
end

return Effect
