local Reflow = {}

local function copy_cell(cell)
  local copy = {}
  for key, value in pairs(cell) do copy[key] = value end
  return copy
end

local function default_blank(cell)
  return cell.glyph == " "
    and not cell.continuation
    and (cell.width == nil or cell.width == 1)
    and cell.codepoints == nil
    and cell.display_text == nil
    and cell.hyperlink_id == nil
    and (cell.flags == nil or cell.flags == 0)
end

local function source_items(source, old_columns, new_columns, is_blank)
  local anchors = {}
  local last = nil
  for column = 0, old_columns - 1 do
    local cell = source.cells[column]
    if cell and not cell.continuation then
      local width = math.max(1, cell.width or 1)
      width = math.min(width, old_columns - column)
      anchors[#anchors + 1] = { cell = cell, column = column, width = width }
      if not is_blank(cell) then last = #anchors end
    end
  end

  local offsets = {}
  local items = {}
  local offset = 0
  for index, anchor in ipairs(anchors) do
    local retained = last ~= nil and index <= last
    local width = retained and (anchor.width > new_columns and 1 or anchor.width) or 0
    for column = anchor.column, math.min(old_columns, anchor.column + anchor.width) do
      offsets[column] = offset + math.min(column - anchor.column, width)
    end
    if retained then
      local cell = copy_cell(anchor.cell)
      cell.width = width
      cell.continuation = nil
      cell.anchor_column = nil
      items[#items + 1] = { cell = cell, column = anchor.column, source_line_id = source.line_id, width = width }
      offset = offset + width
    end
  end
  for column = 0, old_columns do
    if offsets[column] == nil then offsets[column] = offset end
  end
  return items, offsets, offset
end

local function append_source(row, source_line_id)
  local sources = row._reflow_sources
  if sources == nil then
    sources = {}
    row._reflow_sources = sources
  end
  for _, existing in ipairs(sources) do
    if existing == source_line_id then return end
  end
  sources[#sources + 1] = source_line_id
end

local function position_for(segments, offset, columns)
  local selected = segments[1]
  for _, segment in ipairs(segments) do
    if segment.start > offset then break end
    selected = segment
  end
  return {
    column = math.min(columns, math.max(0, offset - selected.start)),
    line_id = selected.row.line_id,
  }
end

-- Rewrap physical rows joined by their wrapped flag. `new_row` supplies a
-- blank row with a fresh line_id; the first resulting segment retains the
-- first source line_id. The returned map translates every old cell-gap
-- coordinate, including blank trailing cells. The membership table maps each
-- source row to the first output row that represents it, for row metadata.
function Reflow.transform(rows, old_columns, new_columns, new_row, is_blank)
  assert(type(rows) == "table" and old_columns >= 1 and new_columns >= 1, "invalid reflow input")
  assert(type(new_row) == "function", "reflow requires a row factory")
  is_blank = is_blank or default_blank

  local output, map, membership, logical = {}, {}, {}, {}
  local function flush()
    if #logical == 0 then return end

    local items, offsets, length = {}, {}, 0
    for _, source in ipairs(logical) do
      local source_items_value, source_offsets, source_length = source_items(source, old_columns, new_columns, is_blank)
      offsets[source.line_id] = { base = length, gaps = source_offsets }
      for _, item in ipairs(source_items_value) do
        item.offset = length + (source_offsets[item.column] or 0)
        items[#items + 1] = item
      end
      length = length + source_length
    end

    local segments = {}
    local segment, column
    local first_segment = true
    local function start(offset)
      local row = new_row()
      if first_segment then
        row.line_id = logical[1].line_id
        first_segment = false
      end
      segment = { row = row, start = offset }
      segments[#segments + 1] = segment
      output[#output + 1] = row
      column = 0
    end

    start(0)
    for _, item in ipairs(items) do
      if column > 0 and column + item.width > new_columns then
        segment.row.wrapped = true
        start(item.offset)
      end
      segment.row.cells[column] = item.cell
      if item.width == 2 and column + 1 < new_columns then
        local continuation = copy_cell(item.cell)
        continuation.glyph, continuation.width, continuation.continuation, continuation.anchor_column = "", 0, true, column
        segment.row.cells[column + 1] = continuation
      end
      column = column + item.width
    end

    for _, source in ipairs(logical) do
      local source_offsets = offsets[source.line_id]
      local entries = {}
      for source_column = 0, old_columns do
        local position = position_for(segments, source_offsets.base + source_offsets.gaps[source_column], new_columns)
        entries[#entries + 1] = {
          column = position.column,
          line_id = position.line_id,
          source_column = source_column,
        }
      end
      map[source.line_id] = entries
      local position = entries[1]
      membership[source.line_id] = position.line_id
      for _, candidate in ipairs(segments) do
        if candidate.row.line_id == position.line_id then
          append_source(candidate.row, source.line_id)
          break
        end
      end
    end
    logical = {}
  end

  for _, row in ipairs(rows) do
    logical[#logical + 1] = row
    if not row.wrapped then flush() end
  end
  flush()
  return output, map, membership
end

function Reflow.remap_position(map, line_id, column, fallback)
  local entries = map[line_id]
  if entries == nil or #entries == 0 then return fallback end
  local selected = entries[1]
  for _, entry in ipairs(entries) do
    if entry.source_column > column then break end
    selected = entry
  end
  return { column = selected.column, line_id = selected.line_id }
end

return Reflow
