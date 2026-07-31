local Errors = require("runtime.errors")
local Manifest = require("effects.manifest")

local Effect = {}
local effect_mt = {}
effect_mt.__index = effect_mt

Effect.contract = {
  constructor = "new(manifest) -> effect | nil, error",
  on_event = "on_event(event) -> nil, error?",
  manifest = "manifest() -> effect_manifest",
  update = "update(visual_time_us) -> nil, error?",
  transform_cell = "transform_cell(visual_cell) -> nil, error?",
  destroy = "destroy()",
}

function Effect.new(manifest)
  local normalised, manifest_error = Manifest.normalise(manifest)
  if not normalised then
    return nil, manifest_error
  end
  return setmetatable({ manifest_value = normalised, state = "bootstrap" }, effect_mt)
end

function effect_mt:manifest()
  return Manifest.copy(self.manifest_value)
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
