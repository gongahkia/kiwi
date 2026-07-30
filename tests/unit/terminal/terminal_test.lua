local assertions = require("support.assertions")
local Terminal = require("terminal.terminal")

local function row_text(row)
  local text = {}
  for column = 1, row.columns do
    text[column] = row.cells[column].text
  end
  return table.concat(text, "|")
end

local function has_event(events, kind, sequence_kind)
  for _, event in ipairs(events) do
    if event.kind == kind and (sequence_kind == nil or event.sequence_kind == sequence_kind) then
      return true
    end
  end
  return false
end

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
  {
    name = "terminal preserves split UTF-8 and replaces malformed input",
    run = function()
      local terminal = assert(Terminal.new({ columns = 4, rows = 1 }))
      assertions.equal(0, #assert(terminal:feed_output("\195")))
      assertions.equal(1, terminal.utf8_decoder:snapshot().remaining)
      assert(terminal:feed_output("\169"))
      assertions.equal("é", terminal.primary_screen.rows[1].cells[1].text)

      assert(terminal:feed_output("\195x"))
      assertions.equal("\239\191\189", terminal.primary_screen.rows[1].cells[2].text)
      assertions.equal("x", terminal.primary_screen.rows[1].cells[3].text)
    end,
  },
  {
    name = "terminal applies CSI cursor movement with defaults and bounds",
    run = function()
      local terminal = assert(Terminal.new({ columns = 5, rows = 4 }))
      assert(terminal:feed_output("\27[3;4H\27[0A\27[99C"))
      assertions.equal(2, terminal.cursor.row)
      assertions.equal(5, terminal.cursor.column)
      assert(terminal:feed_output("\27[2E\27[0F\27[99d"))
      assertions.equal(4, terminal.cursor.row)
      assertions.equal(1, terminal.cursor.column)
      assert(terminal:feed_output("\27[;H"))
      assertions.equal(1, terminal.cursor.row)
      assertions.equal(1, terminal.cursor.column)
    end,
  },
  {
    name = "terminal applies CSI erase and character edit operations",
    run = function()
      local terminal = assert(Terminal.new({ columns = 5, rows = 1 }))
      assert(terminal:feed_output("ABCDE\27[2G\27[2X"))
      assertions.equal("A|||D|E", row_text(terminal.primary_screen.rows[1]))

      terminal = assert(Terminal.new({ columns = 5, rows = 1 }))
      assert(terminal:feed_output("ABCDE\27[3G\27[2@"))
      assertions.equal("A|B|||C", row_text(terminal.primary_screen.rows[1]))

      terminal = assert(Terminal.new({ columns = 5, rows = 1 }))
      assert(terminal:feed_output("ABCDE\27[2G\27[2P"))
      assertions.equal("A|D|E||", row_text(terminal.primary_screen.rows[1]))
    end,
  },
  {
    name = "terminal applies CSI ED and EL modes",
    run = function()
      local terminal = assert(Terminal.new({ columns = 3, rows = 2 }))
      terminal.primary_screen.rows[1].cells[1].text = "A"
      terminal.primary_screen.rows[1].cells[2].text = "B"
      terminal.primary_screen.rows[1].cells[3].text = "C"
      terminal.primary_screen.rows[2].cells[1].text = "D"
      terminal.primary_screen.rows[2].cells[2].text = "E"
      terminal.primary_screen.rows[2].cells[3].text = "F"
      assert(terminal:feed_output("\27[1;2H\27[0J"))
      assertions.equal("A||", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("||", row_text(terminal.primary_screen.rows[2]))

      terminal = assert(Terminal.new({ columns = 3, rows = 1 }))
      assert(terminal:feed_output("ABC\27[2G\27[1K"))
      assertions.equal("||C", row_text(terminal.primary_screen.rows[1]))
      assert(terminal:feed_output("\27[2K"))
      assertions.equal("||", row_text(terminal.primary_screen.rows[1]))
    end,
  },
  {
    name = "terminal applies CSI display line and region scroll edits",
    run = function()
      local terminal = assert(Terminal.new({ columns = 1, rows = 3, scrollback_limit = 2 }))
      terminal.primary_screen.rows[1].cells[1].text = "A"
      terminal.primary_screen.rows[2].cells[1].text = "B"
      terminal.primary_screen.rows[3].cells[1].text = "C"
      assert(terminal:feed_output("\27[2;1H\27[1L"))
      assertions.equal("A", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("", row_text(terminal.primary_screen.rows[2]))
      assertions.equal("B", row_text(terminal.primary_screen.rows[3]))

      terminal = assert(Terminal.new({ columns = 1, rows = 3, scrollback_limit = 2 }))
      terminal.primary_screen.rows[1].cells[1].text = "A"
      terminal.primary_screen.rows[2].cells[1].text = "B"
      terminal.primary_screen.rows[3].cells[1].text = "C"
      assert(terminal:feed_output("\27[2;1H\27[1M"))
      assertions.equal("A", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("C", row_text(terminal.primary_screen.rows[2]))
      assertions.equal("", row_text(terminal.primary_screen.rows[3]))

      terminal = assert(Terminal.new({ columns = 1, rows = 3, scrollback_limit = 2 }))
      terminal.primary_screen.rows[1].cells[1].text = "A"
      terminal.primary_screen.rows[2].cells[1].text = "B"
      terminal.primary_screen.rows[3].cells[1].text = "C"
      assert(terminal:feed_output("\27[1S"))
      assertions.equal("B", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("C", row_text(terminal.primary_screen.rows[2]))
      assertions.equal("", row_text(terminal.primary_screen.rows[3]))
      assertions.equal("A", row_text(assert(terminal.scrollback:at(1))))
      assert(terminal:feed_output("\27[1T"))
      assertions.equal("", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("B", row_text(terminal.primary_screen.rows[2]))
    end,
  },
  {
    name = "terminal applies CSI SGR attributes and colours",
    run = function()
      local terminal = assert(Terminal.new({}))
      assert(terminal:feed_output("\27[1;3;4;5;7;8;9;31;104m"))
      assertions.equal(253, terminal.rendition.attributes)
      assertions.equal(1, terminal.rendition.foreground.index)
      assertions.equal(12, terminal.rendition.background.index)
      assert(terminal:feed_output("\27[22;23;24;25;27;28;29;39;49m"))
      assertions.equal(0, terminal.rendition.attributes)
      assertions.equal("default", terminal.rendition.foreground)
      assertions.equal("default", terminal.rendition.background)
      assert(terminal:feed_output("\27[38;5;196;48;2;1;2;3m"))
      assertions.equal(196, terminal.rendition.foreground.index)
      assertions.equal(1, terminal.rendition.background.red)
      assertions.equal(2, terminal.rendition.background.green)
      assertions.equal(3, terminal.rendition.background.blue)
    end,
  },
  {
    name = "terminal saves and restores DEC cursor and rendition state",
    run = function()
      local terminal = assert(Terminal.new({ columns = 3, rows = 1 }))
      assert(terminal:feed_output("A\27[31m\27" .. "7\27[3G\27[0m\27" .. "8"))
      assertions.equal(2, terminal.cursor.column)
      assertions.equal(1, terminal.rendition.foreground.index)
      assertions.equal("indexed", terminal.rendition.foreground.kind)
    end,
  },
  {
    name = "terminal restores primary state after DEC 1049 alternate screen",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 1 }))
      assert(terminal:feed_output("P\27[?1049h"))
      assertions.equal("alternate", terminal.active_buffer)
      assertions.equal(1, terminal.cursor.column)
      assertions.equal("", terminal.alternate_screen.rows[1].cells[1].text)
      assert(terminal:feed_output("A\27[?1049l"))
      assertions.equal("primary", terminal.active_buffer)
      assertions.equal("P", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal(2, terminal.cursor.column)
      assert(terminal:feed_output("\27[?1049h"))
      assertions.equal("", terminal.alternate_screen.rows[1].cells[1].text)
    end,
  },
  {
    name = "terminal supports alternate variants and cursor mode toggles",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 1 }))
      assert(terminal:feed_output("\27[?47hA\27[?47l\27[?47h"))
      assertions.equal("A", terminal.alternate_screen.rows[1].cells[1].text)
      assert(terminal:feed_output("\27[?25l\27[?7l"))
      assertions.falsy(terminal.modes.cursor_visible)
      assertions.falsy(terminal.modes.auto_wrap)
      assert(terminal:feed_output("BC"))
      assertions.equal("C", terminal.alternate_screen.rows[1].cells[2].text)
      assertions.falsy(terminal.cursor.pending_wrap)
    end,
  },
  {
    name = "terminal reports unsupported sequences without corrupting state",
    run = function()
      local terminal = assert(Terminal.new({ columns = 3, rows = 1 }))
      local events = assert(terminal:feed_output("A\27[999zB"))
      assertions.truthy(has_event(events, "unsupported_sequence", "csi"))
      assertions.equal("A", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal("B", terminal.primary_screen.rows[1].cells[2].text)
      assertions.equal("ground", terminal.parser:snapshot().state)

      events = assert(terminal:feed_output("\27(0\27]0;title\7"))
      assertions.truthy(has_event(events, "unsupported_sequence", "esc"))
      assertions.truthy(has_event(events, "unsupported_sequence", "osc"))
      events = assert(terminal:feed_output("\27[\127m"))
      assertions.truthy(has_event(events, "malformed_sequence"))
      assertions.equal("ground", terminal.parser:snapshot().state)
    end,
  },
}
