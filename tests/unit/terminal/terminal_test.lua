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
  {
    name = "terminal constructor owns an immutable semantic config",
    run = function()
      local terminal = assert(Terminal.new({ columns = 100, rows = 40 }))
      assertions.equal(100, terminal.config.columns)
      assertions.equal(40, terminal.config.rows)
    end,
  },
  {
    name = "terminal owns separate primary and alternate screen buffers",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 1 }))
      terminal.primary_screen.rows[1].cells[1].text = "p"
      assertions.equal("primary", terminal.active_buffer)
      assertions.equal("", terminal.alternate_screen.rows[1].cells[1].text)
    end,
  },
}
