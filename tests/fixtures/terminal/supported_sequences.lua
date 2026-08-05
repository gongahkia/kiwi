local assertions = require("support.assertions")

local function row_text(row)
  local text = {}
  for column = 1, row.columns do
    text[column] = row.cells[column].text
  end
  return table.concat(text, "|")
end

return {
  {
    bytes = "\0\7\b\t\r\n\v\f",
    config = { columns = 9, rows = 4 },
    name = "C0 NUL BEL BS HT LF VT FF CR",
    verify = function(terminal, events)
      assertions.equal("bell", events[1].kind)
      assertions.equal(4, terminal.cursor.row)
      assertions.equal(1, terminal.cursor.column)
    end,
  },
  {
    bytes = "\27[1\24\27[1\26\127",
    config = {},
    name = "C0 CAN SUB DEL",
    verify = function(terminal)
      assertions.equal("ground", terminal.parser:snapshot().state)
    end,
  },
  {
    bytes = "A\27" .. "7\27[3G\27[31m\27" .. "8",
    config = { columns = 3, rows = 1 },
    name = "ESC 7 and ESC 8",
    verify = function(terminal)
      assertions.equal(2, terminal.cursor.column)
      assertions.equal("default", terminal.rendition.foreground)
    end,
  },
  {
    bytes = "\27[3;3H\27[1A\27[1B\27[1C\27[1D\27[1E\27[1F\27[2G\27[2;2f\27[3d",
    config = { columns = 3, rows = 3 },
    name = "CSI cursor movement A B C D E F G H f d",
    verify = function(terminal)
      assertions.equal(3, terminal.cursor.row)
      assertions.equal(2, terminal.cursor.column)
    end,
  },
  {
    bytes = "ABC\27[2G\27[0K",
    config = { columns = 3, rows = 1 },
    name = "CSI EL K",
    verify = function(terminal)
      assertions.equal("A||", row_text(terminal.primary_screen.rows[1]))
    end,
  },
  {
    bytes = "\27[1;2H\27[2J",
    config = { columns = 2, rows = 2 },
    name = "CSI ED J",
    setup = function(terminal)
      terminal.primary_screen.rows[1].cells[1].text = "A"
      terminal.primary_screen.rows[2].cells[2].text = "B"
    end,
    verify = function(terminal)
      assertions.equal("|", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("|", row_text(terminal.primary_screen.rows[2]))
    end,
  },
  {
    bytes = "ABCDE\27[2G\27[2X",
    config = { columns = 5, rows = 1 },
    name = "CSI ECH X",
    verify = function(terminal)
      assertions.equal("A|||D|E", row_text(terminal.primary_screen.rows[1]))
    end,
  },
  {
    bytes = "ABCDE\27[3G\27[1@",
    config = { columns = 5, rows = 1 },
    name = "CSI ICH at",
    verify = function(terminal)
      assertions.equal("A|B||C|D", row_text(terminal.primary_screen.rows[1]))
    end,
  },
  {
    bytes = "ABCDE\27[2G\27[1P",
    config = { columns = 5, rows = 1 },
    name = "CSI DCH P",
    verify = function(terminal)
      assertions.equal("A|C|D|E|", row_text(terminal.primary_screen.rows[1]))
    end,
  },
  {
    bytes = "\27[2;1H\27[1L",
    config = { columns = 1, rows = 3 },
    name = "CSI IL L",
    setup = function(terminal)
      terminal.primary_screen.rows[1].cells[1].text = "A"
      terminal.primary_screen.rows[2].cells[1].text = "B"
    end,
    verify = function(terminal)
      assertions.equal("A", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("", row_text(terminal.primary_screen.rows[2]))
      assertions.equal("B", row_text(terminal.primary_screen.rows[3]))
    end,
  },
  {
    bytes = "\27[2;1H\27[1M",
    config = { columns = 1, rows = 3 },
    name = "CSI DL M",
    setup = function(terminal)
      terminal.primary_screen.rows[1].cells[1].text = "A"
      terminal.primary_screen.rows[2].cells[1].text = "B"
      terminal.primary_screen.rows[3].cells[1].text = "C"
    end,
    verify = function(terminal)
      assertions.equal("A", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("C", row_text(terminal.primary_screen.rows[2]))
      assertions.equal("", row_text(terminal.primary_screen.rows[3]))
    end,
  },
  {
    bytes = "\27[1S",
    config = { columns = 1, rows = 2, scrollback_limit = 1 },
    name = "CSI SU S",
    setup = function(terminal)
      terminal.primary_screen.rows[1].cells[1].text = "A"
      terminal.primary_screen.rows[2].cells[1].text = "B"
    end,
    verify = function(terminal)
      assertions.equal("B", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("A", row_text(assert(terminal.scrollback:at(1))))
    end,
  },
  {
    bytes = "\27[1T",
    config = { columns = 1, rows = 2 },
    name = "CSI SD T",
    setup = function(terminal)
      terminal.primary_screen.rows[1].cells[1].text = "A"
      terminal.primary_screen.rows[2].cells[1].text = "B"
    end,
    verify = function(terminal)
      assertions.equal("", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("A", row_text(terminal.primary_screen.rows[2]))
    end,
  },
  {
    bytes = "\27[1;3;4;5;7;8;9;38;5;196;48;2;1;2;3m\27[0m",
    config = {},
    name = "CSI SGR m",
    verify = function(terminal)
      assertions.equal(0, terminal.rendition.attributes)
      assertions.equal("default", terminal.rendition.foreground)
      assertions.equal("default", terminal.rendition.background)
    end,
  },
  {
    bytes = "\27[?7l\27[?25l\27[?1048h\27[?1048l",
    config = {},
    name = "CSI private cursor modes 7 25 1048",
    verify = function(terminal)
      assertions.falsy(terminal.modes.auto_wrap)
      assertions.falsy(terminal.modes.cursor_visible)
    end,
  },
  {
    bytes = "\27[?47hA\27[?47l\27[?47h",
    config = { columns = 1, rows = 1 },
    name = "CSI alternate screen 47",
    verify = function(terminal)
      assertions.equal("alternate", terminal.active_buffer)
      assertions.equal("A", terminal.alternate_screen.rows[1].cells[1].text)
    end,
  },
  {
    bytes = "\27[?1047hA\27[?1047l",
    config = { columns = 1, rows = 1 },
    name = "CSI alternate screen 1047",
    verify = function(terminal)
      assertions.equal("primary", terminal.active_buffer)
      assertions.equal("", terminal.primary_screen.rows[1].cells[1].text)
    end,
  },
  {
    bytes = "P\27[?1049hA\27[?1049l",
    config = { columns = 1, rows = 1 },
    name = "CSI alternate screen 1049",
    verify = function(terminal)
      assertions.equal("primary", terminal.active_buffer)
      assertions.equal("P", terminal.primary_screen.rows[1].cells[1].text)
    end,
  },
}
