local assertions = require("support.assertions")
local Cell = require("terminal.cell")
local Row = require("terminal.row")

return {
  {
    name = "row creates fixed-width independent blank cells",
    run = function()
      local row = assert(Row.new(3))
      assertions.equal(3, row.columns)
      assertions.equal(0, row.revision)
      assertions.falsy(row.wrapped)
      assertions.equal("", row.cells[1].text)
      row.cells[1].text = "x"
      assertions.equal("", row.cells[2].text)
      assertions.equal(1, select(1, row:dirty_range()))
      assertions.equal(3, select(2, row:dirty_range()))
    end,
  },
  {
    name = "row replacement clones cells and accumulates damage",
    run = function()
      local row = assert(Row.new(4))
      row:clear_damage()
      local first = assert(Cell.new({ text = "a" }))
      assertions.truthy(row:replace(3, first))
      first.text = "b"
      assertions.equal("a", assert(row:get(3)).text)
      assertions.equal(1, row.revision)
      assertions.equal(3, select(1, row:dirty_range()))
      assertions.equal(3, select(2, row:dirty_range()))
      assertions.truthy(row:replace(1, assert(Cell.new({ text = "c" }))))
      assertions.equal(1, select(1, row:dirty_range()))
      assertions.equal(3, select(2, row:dirty_range()))
      assertions.equal(2, row.revision)
    end,
  },
  {
    name = "row clears accumulated damage",
    run = function()
      local row = assert(Row.new(2))
      row:clear_damage()
      assertions.falsy(row:dirty_range())
    end,
  },
  {
    name = "row copy preserves semantics without damage",
    run = function()
      local row = assert(Row.new(1))
      assert(row:replace(1, assert(Cell.new({ text = "a" }))))
      row.wrapped = true
      local copy = assert(Row.copy(row))
      row.cells[1].text = "b"
      assertions.equal("a", copy.cells[1].text)
      assertions.equal(row.revision, copy.revision)
      assertions.truthy(copy.wrapped)
      assertions.falsy(copy:dirty_range())
    end,
  },
  {
    name = "row rejects invalid widths columns and cells",
    run = function()
      local row, row_error = Row.new()
      assertions.falsy(row)
      assertions.equal("config_error", row_error.kind)

      row, row_error = Row.new(0)
      assertions.falsy(row)
      assertions.equal("config_error", row_error.kind)

      row = assert(Row.new(2))
      local cell, cell_error = row:get(3)
      assertions.falsy(cell)
      assertions.equal("config_error", cell_error.kind)
      local replaced, replace_error = row:replace(1, { text = false })
      assertions.falsy(replaced)
      assertions.equal("config_error", replace_error.kind)

      local copy, copy_error = Row.copy({ cells = {}, columns = 1, revision = 0, wrapped = false })
      assertions.falsy(copy)
      assertions.equal("config_error", copy_error.kind)
    end,
  },
}
