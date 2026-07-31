local assertions = require("support.assertions")
local Effect = require("effects.effect")

local function manifest()
  return {
    api_version = 1,
    capabilities = { "lifecycle", "terminal_events" },
    determinism = "deterministic",
    id = "test.effect",
    parameters = {
      enabled = { default = true, type = "boolean" },
      intensity = { default = 0.25, max = 1, min = 0, type = "number" },
      mode = { default = "soft", type = "enum", values = { "soft", "hard" } },
    },
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
  {
    name = "effect owns validated serialisable parameter values",
    run = function()
      local effect = assert(Effect.new(manifest(), nil, { intensity = 0.75, mode = "hard" }))
      local values = effect:parameters()
      assertions.equal(true, values.enabled)
      assertions.equal(0.75, values.intensity)
      assertions.equal("hard", values.mode)
      values.intensity = 0
      assertions.equal(0.75, effect:parameters().intensity)
      assert(effect:set_parameters({ enabled = false, intensity = 0.5 }))
      values = effect:parameters()
      assertions.falsy(values.enabled)
      assertions.equal(0.5, values.intensity)
      assertions.equal("hard", values.mode)
      local value, error_value = effect:set_parameters({ intensity = 2 })
      assertions.falsy(value)
      assertions.equal("effect_load_error", error_value.kind)
      assertions.equal(0.5, effect:parameters().intensity)
      value, error_value = effect:set_parameters({ unknown = true })
      assertions.falsy(value)
      assertions.equal("effect_load_error", error_value.kind)
    end,
  },
}
