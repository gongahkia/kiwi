local Assert = require("tests.assert")
local Reflow = require("kiwi.terminal.reflow")

local function row(id, text, wrapped)
  local cells = {}
  for column = 0, 3 do cells[column] = { glyph = text:sub(column + 1, column + 1) ~= "" and text:sub(column + 1, column + 1) or " ", width = 1 } end
  return { cells = cells, line_id = id, wrapped = wrapped }
end

return {
  reflow_joins_soft_wrapped_rows_and_returns_coordinate_mappings = function()
    local next_id = 10
    local rows, map = Reflow.transform({ row(1, "abcd", true), row(2, "ef", false) }, 4, 3, function()
      next_id = next_id + 1
      return row(next_id, "", false)
    end)
    Assert.equal(#rows, 2)
    Assert.equal(rows[1].cells[0].glyph .. rows[1].cells[1].glyph .. rows[1].cells[2].glyph, "abc")
    Assert.equal(rows[2].cells[0].glyph .. rows[2].cells[1].glyph .. rows[2].cells[2].glyph, "def")
    Assert.equal(map[2][1].line_id, rows[2].line_id)
    local remapped = Reflow.remap_position(map, 2, 1)
    Assert.equal(remapped.line_id, rows[2].line_id)
    Assert.equal(remapped.column, 2)
  end,
  reflow_preserves_each_logical_line_anchor_identity = function()
    local next_id = 20
    local rows = assert(Reflow.transform({ row(1, "a", false), row(2, "b", false) }, 4, 4, function()
      next_id = next_id + 1
      return row(next_id, "", false)
    end))
    Assert.equal(rows[1].line_id, 1)
    Assert.equal(rows[2].line_id, 2)
  end,
}
