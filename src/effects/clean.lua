local Effect = require("effects.effect")
local Errors = require("runtime.errors")

local Clean = {}

Clean.id = "stanczyk.clean"
Clean.contract = {
  new = "new() -> effect | nil, error",
  reset = "reset(effect_host) -> true | nil, error",
}

function Clean.new()
  return Effect.new({
    api_version = 1,
    capabilities = {},
    determinism = "static",
    id = Clean.id,
    parameters = {},
    version = "0.1.0",
  })
end

function Clean.reset(host)
  if
    type(host) ~= "table"
    or type(host.disable) ~= "function"
    or type(host.status) ~= "function"
  then
    return nil, Errors.new("config_error", "clean reset requires an effect host")
  end
  local status = host:status()
  if type(status) ~= "table" or type(status.effects) ~= "table" then
    return nil, Errors.new("config_error", "clean reset effect host status is invalid")
  end
  local clean
  for _, effect in ipairs(status.effects) do
    if
      type(effect) ~= "table"
      or type(effect.id) ~= "string"
      or type(effect.enabled) ~= "boolean"
    then
      return nil, Errors.new("config_error", "clean reset effect status is invalid")
    end
    if effect.id == Clean.id then
      clean = effect
    elseif effect.enabled then
      local disabled, disable_error = host:disable(effect.id)
      if not disabled then
        return nil, disable_error
      end
    end
  end
  if clean and not clean.enabled then
    if type(host.enable) ~= "function" then
      return nil, Errors.new("config_error", "clean reset effect host cannot enable effects")
    end
    return host:enable(Clean.id)
  end
  return true
end

return Clean
