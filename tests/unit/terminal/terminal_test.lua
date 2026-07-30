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
    name = "terminal feed validates output bytes",
    run = function()
      local terminal = assert(Terminal.new({}))
      local value, error_value = terminal:feed_output(nil)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
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
      assertions.equal("ground", terminal.parser:snapshot().state)
    end,
  },
  {
    name = "terminal owns bounded primary-screen scrollback",
    run = function()
      local terminal = assert(Terminal.new({ scrollback_limit = 2 }))
      assertions.equal(2, terminal.scrollback.limit)
      assertions.equal(0, terminal.scrollback.count)
    end,
  },
  {
    name = "terminal applies required C0 control semantics",
    run = function()
      local terminal = assert(Terminal.new({ columns = 10, rows = 2, scrollback_limit = 2 }))
      local events = assert(terminal:feed_output("\0\7"))
      assertions.equal(1, #events)
      assertions.equal("bell", events[1].kind)

      assert(terminal:feed_output("\t"))
      assertions.equal(9, terminal.cursor.column)
      assert(terminal:feed_output("\t"))
      assertions.equal(10, terminal.cursor.column)
      assert(terminal:feed_output("\b\r"))
      assertions.equal(1, terminal.cursor.column)

      terminal.primary_screen.rows[1].cells[1].text = "a"
      assert(terminal:feed_output("\n"))
      assertions.equal(2, terminal.cursor.row)
      events = assert(terminal:feed_output("\v"))
      assertions.equal(1, #events)
      assertions.equal("scrolled", events[1].kind)
      assertions.equal(1, terminal.scrollback.count)
      assertions.equal("a", assert(terminal.scrollback:at(1)).cells[1].text)
      assertions.equal(2, terminal.cursor.row)
    end,
  },
  {
    name = "alternate-screen line feeds do not enter primary scrollback",
    run = function()
      local terminal = assert(Terminal.new({ columns = 1, rows = 1, scrollback_limit = 1 }))
      terminal.active_buffer = "alternate"
      local events = assert(terminal:feed_output("\f"))
      assertions.equal("scrolled", events[1].kind)
      assertions.equal(0, terminal.scrollback.count)
    end,
  },
  {
    name = "terminal writes printable ASCII with deferred autowrap",
    run = function()
      local terminal = assert(Terminal.new({ columns = 3, rows = 2 }))
      local events = assert(terminal:feed_output("abc"))
      assertions.equal(5, #events)
      assertions.equal("a", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal("b", terminal.primary_screen.rows[1].cells[2].text)
      assertions.equal("c", terminal.primary_screen.rows[1].cells[3].text)
      assertions.equal(3, terminal.cursor.column)
      assertions.truthy(terminal.cursor.pending_wrap)

      events = assert(terminal:feed_output("d"))
      assertions.equal(3, #events)
      assertions.equal("cursor_moved", events[1].kind)
      assertions.equal("d", terminal.primary_screen.rows[2].cells[1].text)
      assertions.equal(2, terminal.cursor.column)
      assertions.falsy(terminal.cursor.pending_wrap)
    end,
  },
  {
    name = "terminal copies current rendition into printable ASCII cells",
    run = function()
      local terminal = assert(Terminal.new({ columns = 1, rows = 1 }))
      terminal.rendition.attributes = 1
      terminal.rendition.foreground = { index = 196, kind = "indexed" }
      assert(terminal:feed_output("x"))
      local cell = terminal.primary_screen.rows[1].cells[1]
      terminal.rendition.foreground.index = 0
      assertions.equal(1, cell.attributes)
      assertions.equal(196, cell.foreground.index)
      assertions.equal("x", cell.text)
    end,
  },
}
