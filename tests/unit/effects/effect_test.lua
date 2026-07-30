local assertions = require("support.assertions")
local Effect = require("effects.effect")

return {
  {
    name = "effect constructor requires manifest id",
    run = function()
      local effect, error_value = Effect.new({})
      assertions.falsy(effect)
      assertions.equal("effect_load_error", error_value.kind)
    end,
  },
  {
    name = "effect bootstrap does not mutate semantic events",
    run = function()
      local effect = assert(Effect.new({ id = "test.effect" }))
      local event = { kind = "output", data = "hello" }
      local value, error_value = effect:on_event(event)
      assertions.falsy(value)
      assertions.equal("effect_runtime_error", error_value.kind)
      assertions.equal("hello", event.data)
    end,
  },
}
