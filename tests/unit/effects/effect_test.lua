local assertions = require("support.assertions")
local Effect = require("effects.effect")

local function manifest()
  return {
    api_version = 1,
    capabilities = { "terminal_events" },
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
    name = "effect bootstrap does not mutate semantic events",
    run = function()
      local source = manifest()
      local effect = assert(Effect.new(source))
      source.capabilities[1] = "draw_after"
      local definition = effect:manifest()
      assertions.equal("terminal_events", definition.capabilities[1])
      definition.capabilities[1] = "draw_after"
      assertions.equal("terminal_events", effect:manifest().capabilities[1])
      local event = { kind = "output", data = "hello" }
      local value, error_value = effect:on_event(event)
      assertions.falsy(value)
      assertions.equal("effect_runtime_error", error_value.kind)
      assertions.equal("hello", event.data)
    end,
  },
}
