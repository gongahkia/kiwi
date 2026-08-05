local assertions = require("support.assertions")
local Errors = require("runtime.errors")

return {
  {
    name = "errors creates known structured errors",
    run = function()
      local error_value =
        assert(Errors.new("config_error", "invalid configuration", { field = "columns" }))
      assertions.equal("config_error", error_value.kind)
      assertions.equal("invalid configuration", error_value.message)
      assertions.truthy(Errors.is(error_value))
    end,
  },
  {
    name = "errors rejects unknown taxonomy kinds",
    run = function()
      local value, error_value = Errors.new("unknown", "invalid")
      assertions.falsy(value)
      assertions.equal("internal_invariant_error", error_value.kind)
      assertions.truthy(Errors.is(error_value))
    end,
  },
}
