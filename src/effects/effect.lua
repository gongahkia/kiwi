local Errors = require("runtime.errors")
local Manifest = require("effects.manifest")

local Effect = {}
local effect_mt = {}
effect_mt.__index = effect_mt

local hook_capabilities = {
  after_canvas = "canvas_after",
  before_canvas = "canvas_before",
  init = "lifecycle",
  needs_redraw = "visual_state",
  on_cell = "cell_observation",
  on_event = "terminal_events",
  shutdown = "lifecycle",
  transform_cell = "cell_transform",
  update = "frame_update",
}

Effect.contract = {
  constructor = "new(manifest, hooks?, parameters?) -> effect | nil, error",
  hook = "hook(name) -> callback | nil",
  manifest = "manifest() -> effect_manifest",
  parameters = "parameters() -> parameter_values",
  set_parameters = "set_parameters(values) -> true | nil, error",
  destroy = "destroy()",
}

function Effect.new(manifest, hooks, parameters)
  local normalised, manifest_error = Manifest.normalise(manifest)
  if not normalised then
    return nil, manifest_error
  end
  if hooks == nil then
    hooks = {}
  end
  if type(hooks) ~= "table" then
    return nil, Errors.new("effect_load_error", "effect hooks must be a table")
  end
  local parameter_values, parameter_error = Manifest.parameters(normalised, parameters)
  if not parameter_values then
    return nil, parameter_error
  end
  local granted = {}
  for _, capability in ipairs(normalised.capabilities) do
    granted[capability] = true
  end
  local copied_hooks = {}
  for name, callback in pairs(hooks) do
    local capability = hook_capabilities[name]
    if not capability then
      return nil, Errors.new("effect_load_error", "effect hook is unsupported", { hook = name })
    end
    if type(callback) ~= "function" then
      return nil, Errors.new("effect_load_error", "effect hook must be a function", { hook = name })
    end
    if not granted[capability] then
      return nil,
        Errors.new("effect_load_error", "effect hook capability is undeclared", {
          capability = capability,
          hook = name,
        })
    end
    copied_hooks[name] = callback
  end
  return setmetatable({
    hooks = copied_hooks,
    manifest_value = normalised,
    parameter_values = parameter_values,
    state = "bootstrap",
  }, effect_mt)
end

function effect_mt:manifest()
  return Manifest.copy(self.manifest_value)
end

function effect_mt:parameters()
  return Manifest.parameters(self.manifest_value, {}, self.parameter_values)
end

function effect_mt:set_parameters(values)
  local parameter_values, parameter_error =
    Manifest.parameters(self.manifest_value, values, self.parameter_values)
  if not parameter_values then
    return nil, parameter_error
  end
  self.parameter_values = parameter_values
  return true
end

function effect_mt:hook(name)
  return self.hooks[name]
end

function effect_mt:destroy()
  self.state = "destroyed"
end

return Effect
