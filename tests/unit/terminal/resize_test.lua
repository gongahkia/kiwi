local assertions = require("support.assertions")
local Cell = require("terminal.cell")
local Terminal = require("terminal.terminal")

local function put(screen, row, column, text, options)
  options = options or {}
  options.text = text
  assert(screen.rows[row]:replace(column, assert(Cell.new(options))))
end

local function row_text(row)
  local values = {}
  for column = 1, row.columns do
    values[column] = row.cells[column].text
  end
  return table.concat(values, "|")
end

local function fill(screen, prefix)
  for row = 1, screen.height do
    for column = 1, screen.columns do
      put(screen, row, column, prefix .. row .. column)
    end
  end
end

local function blank(cell)
  assertions.equal("", cell.text)
  assertions.equal(1, cell.width)
  assertions.falsy(cell.continuation)
  assertions.equal(0, cell.attributes)
  assertions.equal("default", cell.foreground)
  assertions.equal("default", cell.background)
end

local function tab_stops(terminal)
  local values = {}
  for column = 1, terminal.config.columns do
    if terminal.tab_stops[column] then
      values[#values + 1] = column
    end
  end
  return table.concat(values, ",")
end

local function scrollback_signature(terminal)
  local values = { terminal.scrollback.count, terminal.scrollback.first, terminal.scrollback.limit }
  for index = 1, terminal.scrollback.count do
    local row = assert(terminal.scrollback:at(index))
    values[#values + 1] = row.columns
    values[#values + 1] = tostring(row.wrapped)
    for column = 1, row.columns do
      local cell = row.cells[column]
      values[#values + 1] = cell.text
      values[#values + 1] = cell.width
      values[#values + 1] = tostring(cell.continuation)
      values[#values + 1] = cell.attributes
      values[#values + 1] = cell.foreground == "default" and "default" or cell.foreground.index
      values[#values + 1] = cell.background == "default" and "default" or cell.background.index
    end
  end
  return table.concat(values, "\0")
end

return {
  {
    name = "terminal resize is a semantic no-op at the current size",
    run = function()
      local terminal = assert(Terminal.new({ columns = 3, rows = 2 }))
      assert(terminal:feed_output("abc"))
      local digest = assert(terminal:digest())
      local config = terminal.config
      local primary = terminal.primary_screen
      local alternate = terminal.alternate_screen
      assertions.truthy(terminal:resize(3, 2))
      assertions.equal(digest, assert(terminal:digest()))
      assertions.equal(config, terminal.config)
      assertions.equal(primary, terminal.primary_screen)
      assertions.equal(alternate, terminal.alternate_screen)
    end,
  },
  {
    name = "terminal resize preserves the top-left rectangle on width shrink",
    run = function()
      local terminal = assert(Terminal.new({ columns = 3, rows = 2 }))
      fill(terminal.primary_screen, "P")
      assertions.truthy(terminal:resize(2, 2))
      assertions.equal("P11|P12", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("P21|P22", row_text(terminal.primary_screen.rows[2]))
      assertions.truthy(terminal:resize(3, 2))
      blank(terminal.primary_screen.rows[1].cells[3])
      blank(terminal.primary_screen.rows[2].cells[3])
    end,
  },
  {
    name = "terminal resize preserves upper rows on height shrink",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 3 }))
      fill(terminal.primary_screen, "P")
      assertions.truthy(terminal:resize(2, 2))
      assertions.equal("P11|P12", row_text(terminal.primary_screen.rows[1]))
      assertions.equal("P21|P22", row_text(terminal.primary_screen.rows[2]))
      assertions.truthy(terminal:resize(2, 3))
      assertions.equal("|", row_text(terminal.primary_screen.rows[3]))
    end,
  },
  {
    name = "terminal resize expands with canonical default cells",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 1 }))
      put(terminal.primary_screen, 1, 1, "A", { attributes = 1 })
      put(terminal.primary_screen, 1, 2, "B", { foreground = { index = 2, kind = "indexed" } })
      assertions.truthy(terminal:resize(4, 3))
      assertions.equal("A", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal(1, terminal.primary_screen.rows[1].cells[1].attributes)
      assertions.equal("B", terminal.primary_screen.rows[1].cells[2].text)
      assertions.equal(2, terminal.primary_screen.rows[1].cells[2].foreground.index)
      for row = 1, 3 do
        local first = row == 1 and 3 or 1
        for column = first, 4 do
          blank(terminal.primary_screen.rows[row].cells[column])
        end
      end
    end,
  },
  {
    name = "terminal resize applies the intersection rule during combined changes",
    run = function()
      local terminal = assert(Terminal.new({ columns = 4, rows = 4 }))
      fill(terminal.primary_screen, "P")
      assertions.truthy(terminal:resize(6, 2))
      for row = 1, 2 do
        for column = 1, 4 do
          assertions.equal(
            "P" .. row .. column,
            terminal.primary_screen.rows[row].cells[column].text
          )
        end
        blank(terminal.primary_screen.rows[row].cells[5])
        blank(terminal.primary_screen.rows[row].cells[6])
      end
    end,
  },
  {
    name = "terminal resize preserves primary and alternate screens independently",
    run = function()
      local terminal = assert(Terminal.new({ columns = 3, rows = 2 }))
      fill(terminal.primary_screen, "P")
      fill(terminal.alternate_screen, "A")
      terminal.active_buffer = "alternate"
      assertions.truthy(terminal:resize(2, 3))
      assertions.equal("P11", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal("A11", terminal.alternate_screen.rows[1].cells[1].text)
      assertions.equal("P22", terminal.primary_screen.rows[2].cells[2].text)
      assertions.equal("A22", terminal.alternate_screen.rows[2].cells[2].text)
      blank(terminal.primary_screen.rows[3].cells[1])
      blank(terminal.alternate_screen.rows[3].cells[1])
      assertions.equal("alternate", terminal.active_buffer)
    end,
  },
  {
    name = "terminal resize clamps active and saved cursors and clears wraps",
    run = function()
      for _, coordinates in ipairs({
        { column = 1, row = 1 },
        { column = 4, row = 1 },
        { column = 1, row = 4 },
        { column = 4, row = 4 },
      }) do
        local terminal = assert(Terminal.new({ columns = 4, rows = 4 }))
        terminal.cursor.column = coordinates.column
        terminal.cursor.pending_wrap = true
        terminal.cursor.row = coordinates.row
        terminal.saved_cursor.column = coordinates.column
        terminal.saved_cursor.pending_wrap = true
        terminal.saved_cursor.row = coordinates.row
        assertions.truthy(terminal:resize(2, 2))
        assertions.equal(math.min(coordinates.column, 2), terminal.cursor.column)
        assertions.equal(math.min(coordinates.row, 2), terminal.cursor.row)
        assertions.falsy(terminal.cursor.pending_wrap)
        assertions.equal(math.min(coordinates.column, 2), terminal.saved_cursor.column)
        assertions.equal(math.min(coordinates.row, 2), terminal.saved_cursor.row)
        assertions.falsy(terminal.saved_cursor.pending_wrap)
      end
    end,
  },
  {
    name = "terminal resize resets margins and default tab stops",
    run = function()
      local terminal = assert(Terminal.new({ columns = 10, rows = 4 }))
      terminal.margins = { top = 2, bottom = 3 }
      terminal.tab_stops[2] = true
      assertions.truthy(terminal:resize(7, 2))
      assertions.equal(1, terminal.margins.top)
      assertions.equal(2, terminal.margins.bottom)
      assertions.equal("", tab_stops(terminal))
      assertions.truthy(terminal:resize(8, 2))
      assertions.equal("", tab_stops(terminal))
      assertions.truthy(terminal:resize(9, 2))
      assertions.equal("9", tab_stops(terminal))
      assertions.truthy(terminal:resize(17, 2))
      assertions.equal("9,17", tab_stops(terminal))
    end,
  },
  {
    name = "terminal resize leaves scrollback structurally unchanged",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 1, scrollback_limit = 2 }))
      assert(terminal:feed_output("\27[31mAB\nCD\n"))
      local before = scrollback_signature(terminal)
      assertions.truthy(terminal:resize(3, 2))
      assertions.equal(before, scrollback_signature(terminal))
      assertions.equal(2, assert(terminal.scrollback:at(1)).columns)
    end,
  },
  {
    name = "terminal resize preserves modes and parser continuation state",
    run = function()
      local terminal = assert(Terminal.new({ columns = 4, rows = 2 }))
      assert(terminal:feed_output("\27[?7l\27[?25l\27[31"))
      local parser = terminal.parser:snapshot()
      assertions.truthy(terminal:resize(3, 3))
      assertions.falsy(terminal.modes.auto_wrap)
      assertions.falsy(terminal.modes.cursor_visible)
      assertions.equal(parser.byte_offset, terminal.parser:snapshot().byte_offset)
      assertions.equal(parser.csi_parameters, terminal.parser:snapshot().csi_parameters)
      assertions.equal(parser.state, terminal.parser:snapshot().state)
    end,
  },
  {
    name = "terminal resize rejects invalid dimensions without mutation",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 2 }))
      fill(terminal.primary_screen, "P")
      local digest = assert(terminal:digest())
      for _, dimensions in ipairs({ { 0, 1 }, { 1, 0 }, { -1, 1 }, { 1001, 1 }, { 1, 1001 } }) do
        local value, error_value = terminal:resize(dimensions[1], dimensions[2])
        assertions.falsy(value)
        assertions.equal("config_error", error_value.kind)
        assertions.equal(digest, assert(terminal:digest()))
      end
    end,
  },
  {
    name = "terminal resize repairs wide cells at a new right edge",
    run = function()
      local terminal = assert(Terminal.new({ columns = 3, rows = 1 }))
      put(terminal.primary_screen, 1, 2, "界", { width = 2 })
      put(terminal.primary_screen, 1, 3, "", { continuation = true, width = 0 })
      assertions.truthy(terminal:resize(2, 1))
      blank(terminal.primary_screen.rows[1].cells[2])
    end,
  },
  {
    name = "terminal resize does not restore cells discarded by a prior shrink",
    run = function()
      local terminal = assert(Terminal.new({ columns = 3, rows = 2 }))
      fill(terminal.primary_screen, "P")
      assertions.truthy(terminal:resize(2, 1))
      assertions.truthy(terminal:resize(3, 2))
      assertions.equal("P11", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal("P12", terminal.primary_screen.rows[1].cells[2].text)
      blank(terminal.primary_screen.rows[1].cells[3])
      blank(terminal.primary_screen.rows[2].cells[1])
    end,
  },
}
