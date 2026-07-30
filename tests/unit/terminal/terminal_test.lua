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
  {
    name = "terminal initialises cursor margins tabs and rendition",
    run = function()
      local terminal = assert(Terminal.new({ columns = 20, rows = 5 }))
      assertions.equal(1, terminal.cursor.column)
      assertions.equal(1, terminal.cursor.row)
      assertions.equal(1, terminal.saved_cursor.column)
      assertions.equal(1, terminal.margins.top)
      assertions.equal(5, terminal.margins.bottom)
      assertions.truthy(terminal.tab_stops[9])
      assertions.truthy(terminal.tab_stops[17])
      assertions.falsy(terminal.tab_stops[1])
      assertions.equal(0, terminal.rendition.attributes)
      assertions.equal("default", terminal.rendition.foreground)
    end,
  },
}
