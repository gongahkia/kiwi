local assertions = require("support.assertions")
local Cell = require("terminal.cell")
local Row = require("terminal.row")
local Scrollback = require("terminal.scrollback")

local function row_with_text(text)
  local row = assert(Row.new(1))
  assert(row:replace(1, assert(Cell.new({ text = text }))))
  return row
end

return {
  {
    name = "scrollback retains the newest rows within its limit",
    run = function()
      local scrollback = assert(Scrollback.new(2))
      assert(scrollback:push(row_with_text("a")))
      assert(scrollback:push(row_with_text("b")))
      assert(scrollback:push(row_with_text("c")))
      assertions.equal(2, scrollback.count)
      assertions.equal("b", assert(scrollback:at(1)).cells[1].text)
      assertions.equal("c", assert(scrollback:at(2)).cells[1].text)
    end,
  },
  {
    name = "scrollback snapshots source and returned rows",
    run = function()
      local scrollback = assert(Scrollback.new(1))
      local source = row_with_text("a")
      assert(scrollback:push(source))
      source.cells[1].text = "b"
      local stored = assert(scrollback:at(1))
      stored.cells[1].text = "c"
      assertions.equal("a", assert(scrollback:at(1)).cells[1].text)
    end,
  },
  {
    name = "zero-limit scrollback stores no rows",
    run = function()
      local scrollback = assert(Scrollback.new(0))
      assert(scrollback:push(row_with_text("a")))
      assertions.equal(0, scrollback.count)
      local row, error_value = scrollback:at(1)
      assertions.falsy(row)
      assertions.equal("config_error", error_value.kind)
    end,
  },
  {
    name = "scrollback rejects invalid limits rows and indexes",
    run = function()
      local scrollback, limit_error = Scrollback.new(-1)
      assertions.falsy(scrollback)
      assertions.equal("config_error", limit_error.kind)

      scrollback = assert(Scrollback.new(1))
      local pushed, row_error = scrollback:push(nil)
      assertions.falsy(pushed)
      assertions.equal("config_error", row_error.kind)
      local row, index_error = scrollback:at(1)
      assertions.falsy(row)
      assertions.equal("config_error", index_error.kind)
    end,
  },
}
