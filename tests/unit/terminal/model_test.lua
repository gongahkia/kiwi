local assertions = require("support.assertions")
local Terminal = require("terminal.terminal")

local function row_text(row)
  local text = {}
  for column = 1, row.columns do
    text[column] = row.cells[column].text
  end
  return table.concat(text, "|")
end

local function set_row_text(terminal, values)
  for row, value in ipairs(values) do
    terminal.primary_screen.rows[row].cells[1].text = value
  end
end

local function has_scroll_event(events, top, bottom)
  for _, event in ipairs(events) do
    if event.kind == "scrolled" and event.top == top and event.bottom == bottom then
      return true
    end
  end
  return false
end

return {
  {
    name = "terminal scrolls only within configured margins",
    run = function()
      local terminal = assert(Terminal.new({ columns = 1, rows = 4, scrollback_limit = 2 }))
      set_row_text(terminal, { "A", "B", "C", "D" })
      terminal.margins = { top = 2, bottom = 3 }
      terminal.cursor.row = 3
      local events = assert(terminal:feed_output("\n"))
      assertions.equal("A", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("C", row_text(terminal.primary_screen.rows[2]))
      assertions.equal("", row_text(terminal.primary_screen.rows[3]))
      assertions.equal("D", row_text(terminal.primary_screen.rows[4]))
      assertions.equal(0, terminal.scrollback.count)
      assertions.truthy(has_scroll_event(events, 2, 3))
    end,
  },
  {
    name = "terminal line edits remain within configured margins",
    run = function()
      local terminal = assert(Terminal.new({ columns = 1, rows = 4 }))
      set_row_text(terminal, { "A", "B", "C", "D" })
      terminal.margins = { top = 2, bottom = 3 }
      terminal.cursor.row = 1
      assert(terminal:feed_output("\27[1L"))
      assertions.equal("A", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("B", row_text(terminal.primary_screen.rows[2]))
      assertions.equal("C", row_text(terminal.primary_screen.rows[3]))
      assertions.equal("D", row_text(terminal.primary_screen.rows[4]))

      terminal.cursor.row = 2
      assert(terminal:feed_output("\27[1L"))
      assertions.equal("A", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("", row_text(terminal.primary_screen.rows[2]))
      assertions.equal("B", row_text(terminal.primary_screen.rows[3]))
      assertions.equal("D", row_text(terminal.primary_screen.rows[4]))
    end,
  },
  {
    name = "terminal erase uses the current rendition without moving the cursor",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 2 }))
      set_row_text(terminal, { "A", "C" })
      terminal.primary_screen.rows[1].cells[2].text = "B"
      terminal.primary_screen.rows[2].cells[2].text = "D"
      terminal.cursor.row = 1
      terminal.cursor.column = 2
      assert(terminal:feed_output("\27[32m\27[0J"))
      assertions.equal("A|", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("|", row_text(terminal.primary_screen.rows[2]))
      assertions.equal(1, terminal.cursor.row)
      assertions.equal(2, terminal.cursor.column)
      assertions.equal("indexed", terminal.primary_screen.rows[1].cells[2].foreground.kind)
      assertions.equal(2, terminal.primary_screen.rows[1].cells[2].foreground.index)
      assertions.equal(2, terminal.primary_screen.rows[2].cells[1].foreground.index)
    end,
  },
  {
    name = "terminal alternate transitions preserve and clear the documented buffers",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 1 }))
      assert(terminal:feed_output("P\27[?47hA\27[?47l"))
      assertions.equal("P", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal("A", terminal.alternate_screen.rows[1].cells[2].text)

      assert(terminal:feed_output("\27[?1047hB\27[?1047l"))
      assertions.equal("P", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal("B", terminal.alternate_screen.rows[1].cells[1].text)

      assert(terminal:feed_output("\27[?1049hC\27[?1049l"))
      assertions.equal("primary", terminal.active_buffer)
      assertions.equal("P", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal("C", terminal.alternate_screen.rows[1].cells[1].text)
      assertions.equal(2, terminal.cursor.column)
    end,
  },
}
