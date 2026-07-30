local assertions = require("support.assertions")
local Terminal = require("terminal.terminal")

return {
  {
    name = "terminal constructor requires table configuration",
    run = function()
      local terminal, error_value = Terminal.new(nil)
      assertions.falsy(terminal)
      assertions.equal("config_error", error_value.kind)
    end,
  },
  {
    name = "terminal bootstrap instance reports unimplemented parser",
    run = function()
      local terminal = assert(Terminal.new({}))
      local value, error_value = terminal:feed_output("hello")
      assertions.falsy(value)
      assertions.equal("internal_invariant_error", error_value.kind)
    end,
  },
}
