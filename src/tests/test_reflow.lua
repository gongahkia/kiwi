local Assert = require("tests.assert")
local Reflow = require("kiwi.terminal.reflow")

local function row(id, text, wrapped)
  local cells = {}
  for column = 0, 3 do cells[column] = { glyph = text:sub(column + 1, column + 1) ~= "" and text:sub(column + 1, column + 1) or " ", width = 1 } end
  return { cells = cells, line_id = id, wrapped = wrapped }
end

return {
  sparse_reflow_preserves_wide_text_gap_mapping_and_allocates_only_unused_cells = function()
    local first, second = row(1, "A  B", true), row(2, "C", false)
    first.cells[1] = { glyph = "界", width = 2, fg = 42, underline_color = 123, underline_style = 3 }
    first.cells[2] = { glyph = "", width = 0, continuation = true, anchor_column = 1 }
    local next_id, blanks = 10, 0
    local rows, map, membership = Reflow.transform({ first, second }, 4, 3, function()
      next_id = next_id + 1
      return { cells = {}, line_id = next_id, wrapped = false }
    end, nil, { compact_map = true, blank_cell = function()
      blanks = blanks + 1
      return { glyph = " ", width = 1 }
    end })
    Assert.equal(#rows, 2)
    Assert.equal(blanks, 1)
    Assert.equal(rows[1].line_id, 1)
    Assert.equal(rows[1].cells[0].glyph, "A")
    Assert.equal(rows[1].cells[1].glyph, "界")
    Assert.equal(rows[1].cells[2].continuation, true)
    Assert.equal(rows[1].cells[2].anchor_column, 1)
    Assert.equal(rows[1].cells[2].fg, 42)
    Assert.equal(rows[1].cells[2].underline_color, 123)
    Assert.equal(rows[1].wrapped, true)
    Assert.equal(rows[2].cells[0].glyph .. rows[2].cells[1].glyph .. rows[2].cells[2].glyph, "BC ")
    Assert.equal(rows[2].wrapped, false)
    Assert.equal(membership[2], rows[2].line_id)
    for _, expected in ipairs({ {1, 0, 1, 0}, {1, 2, 1, 2}, {1, 3, 2, 0}, {2, 0, 2, 1}, {2, 4, 2, 2} }) do
      local mapped = Reflow.remap_position(map, expected[1], expected[2])
      Assert.equal(mapped.line_id, rows[expected[3]].line_id)
      Assert.equal(mapped.column, expected[4])
    end
    rows[1].cells[1].glyph = "X"
    Assert.equal(first.cells[1].glyph, "界")
  end,
  compact_reflow_mapping_matches_every_dense_gap_across_wide_and_wrapped_lines = function()
    local sources = { row(1, "abcd", true), row(2, "ef", false), row(3, "  ", false), row(4, "ghi", true) }
    sources[2].cells[0] = { glyph = "界", width = 2 }
    sources[2].cells[1] = { glyph = "", continuation = true, width = 0, anchor_column = 0 }
    for columns = 1, 8 do
      local function transform(compact)
        local next_id = 10
        return Reflow.transform(sources, 4, columns, function()
          next_id = next_id + 1
          local value = row(next_id, "", false)
          for column = 4, columns - 1 do value.cells[column] = { glyph = " ", width = 1 } end
          return value
        end, nil, { compact_map = compact })
      end
      local dense_rows, dense, dense_members = transform(false)
      local compact_rows, compact, compact_members = transform(true)
      Assert.equal(#compact_rows, #dense_rows)
      for _, source in ipairs(sources) do
        Assert.equal(compact_members[source.line_id], dense_members[source.line_id])
        for column = -1, 6, 0.5 do
          local expected = Reflow.remap_position(dense, source.line_id, column)
          local actual = Reflow.remap_position(compact, source.line_id, column)
          Assert.equal(actual.column, expected.column)
          Assert.equal(actual.line_id, expected.line_id)
        end
      end
      Assert.equal(Reflow.remap_position(compact, 999, 0, "missing"), "missing")
    end
  end,
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
  reflow_maps_blank_cell_gaps_and_flushes_a_trailing_soft_wrapped_line = function()
    local next_id = 30
    local source = row(1, "a", true)
    local rows, map = Reflow.transform({ source }, 4, 3, function()
      next_id = next_id + 1
      return row(next_id, "", false)
    end)
    Assert.equal(#rows, 1)
    local gap = Reflow.remap_position(map, source.line_id, 4)
    Assert.equal(gap.line_id, rows[1].line_id)
    Assert.equal(gap.column, 1)
  end,
}
