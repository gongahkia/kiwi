local assertions = require("support.assertions")
local Effect = require("effects.effect")

local function manifest()
  return {
    api_version = 1,
    capabilities = { "lifecycle", "terminal_events" },
    determinism = "deterministic",
    id = "test.effect",
    parameters = {},
    version = "0.1.0",
  }
end

return {
  {
    name = "effect constructor requires a complete valid manifest",
    run = function()
      local effect, error_value = Effect.new({})
      assertions.falsy(effect)
      assertions.equal("effect_load_error", error_value.kind)
      local valid = manifest()
      valid.id = ""
      effect, error_value = Effect.new(valid)
      assertions.falsy(effect)
      assertions.equal("effect_load_error", error_value.kind)
    end,
  },
  {
    name = "effect hooks require declared lifecycle capabilities",
    run = function()
      local source = manifest()
      local effect = assert(Effect.new(source, {
        on_event = function() end,
      }))
      source.capabilities[1] = "draw_after"
      local definition = effect:manifest()
      assertions.equal("lifecycle", definition.capabilities[1])
      definition.capabilities[1] = "draw_after"
      assertions.equal("lifecycle", effect:manifest().capabilities[1])
      local value, error_value = Effect.new(manifest(), {
        update = function() end,
      })
      assertions.falsy(value)
      assertions.equal("effect_load_error", error_value.kind)
    end,
  },
}
