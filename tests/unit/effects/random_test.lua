local assertions = require("support.assertions")
local Random = require("effects.random")

return {
  {
    name = "effect random produces the documented xorshift32 sequence",
    run = function()
      local random = assert(Random.new(1))
      assertions.equal(270369, random:next_u32())
      assertions.equal(67634689, random:next_u32())
      assertions.equal(2647435461, random:next_u32())
      assertions.equal(307599695, random:next_u32())
      assertions.equal(2637309462, assert(Random.derive(7, "test.effect")))
      assertions.falsy(Random.derive(7, ""))
    end,
  },
  {
    name = "effect random bounds unbiased integer requests",
    run = function()
      local random = assert(Random.new(1))
      for _ = 1, 32 do
        local value = assert(random:integer(-4, 3))
        assertions.truthy(value >= -4 and value <= 3)
      end
      assertions.equal(-2147213279, assert(Random.new(1):integer(-2147483648, 2147483647)))
      local value, error_value = random:integer(3, 2)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      value, error_value = Random.new(-1)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
    end,
  },
}
