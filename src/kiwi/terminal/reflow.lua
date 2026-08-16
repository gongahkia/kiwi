local Reflow = {}

local function copy_cell(cell)
  local copy = {}
  for key, value in pairs(cell) do copy[key] = value end
  return copy
end

local function clusters(row, columns)
  local result = {}
  for column = 0, columns - 1 do
    local cell = row.cells[column]
    if not cell.continuation then
      result[#result + 1] = { cell = copy_cell(cell), column = column, width = math.max(1, cell.width or 1) }
    end
  end
  while #result > 0 and result[#result].cell.glyph == " " do table.remove(result) end
  return result
end

-- Rewrap physical rows joined by their wrapped flag. `new_row` supplies a
-- blank row with a fresh line_id; the first resulting segment retains the
-- first source line_id, and `map` translates every old cell-gap coordinate.
function Reflow.transform(rows, old_columns, new_columns, new_row)
  assert(type(rows) == "table" and old_columns >= 1 and new_columns >= 1, "invalid reflow input")
  local output, map, logical = {}, {}, {}
  for _, row in ipairs(rows) do
    logical[#logical + 1] = row
    if not row.wrapped then
      local items = {}
      for _, source in ipairs(logical) do
        for _, item in ipairs(clusters(source, old_columns)) do
          item.source_line_id = source.line_id
          items[#items + 1] = item
        end
      end
      local segment, column = nil, 0
      local first_segment = true
      local function start()
        segment = new_row()
        if first_segment then
          segment.line_id = logical[1].line_id
          first_segment = false
        end
        output[#output + 1] = segment
        column = 0
      end
      start()
      for _, item in ipairs(items) do
        if column > 0 and column + item.width > new_columns then
          segment.wrapped = true
          start()
        end
        if item.width > new_columns then item.width = 1 end
        segment.cells[column] = item.cell
        if item.width == 2 and column + 1 < new_columns then
          local continuation = copy_cell(item.cell)
          continuation.glyph, continuation.width, continuation.continuation, continuation.anchor_column = "", 0, true, column
          segment.cells[column + 1] = continuation
        end
        map[item.source_line_id] = map[item.source_line_id] or {}
        map[item.source_line_id][#map[item.source_line_id] + 1] = { column = column, line_id = segment.line_id, source_column = item.column }
        column = column + item.width
      end
      logical = {}
    end
  end
  return output, map
end

function Reflow.remap_position(map, line_id, column, fallback)
  local entries = map[line_id]
  if entries == nil or #entries == 0 then return fallback end
  local selected = entries[1]
  for _, entry in ipairs(entries) do
    if entry.source_column > column then break end
    selected = entry
  end
  return { column = selected.column + math.max(0, column - selected.source_column), line_id = selected.line_id }
end

return Reflow
