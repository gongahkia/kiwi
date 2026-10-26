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

local function last_content_column(source, old_columns, is_blank, context)
  local last
  for column = 0, old_columns - 1 do
    local cell = source.cells[column]
    if cell and not cell.continuation and not is_blank(cell, context) then last = column end
  end
  return last
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

-- Keep hot helpers shared: per-operation closures can become JIT constants
-- and retain entire discarded reflow documents through their upvalues.
local function start_segment(output, segments, logical, new_row, context, offset)
  local row = new_row(context)
  if #segments == 0 then row.line_id = logical[1].line_id end
  local segment = { row = row, start = offset }
  segments[#segments + 1] = segment
  output[#output + 1] = row
  return segment, 0
end

local function flush(logical, output, map, membership, old_columns, new_columns,
    new_row, is_blank, blank_cell, compact_map, context)
  if #logical == 0 then return end
  local offsets, length, segments = {}, 0, {}
  local segment, column = start_segment(output, segments, logical, new_row, context, 0)
  for _, source in ipairs(logical) do
    local last = last_content_column(source, old_columns, is_blank, context)
    local gaps, base = {}, length
    -- Emit directly into destination rows. The old implementation allocated
    -- both an anchor and an item table for every retained source character.
    for source_column = 0, old_columns - 1 do
      local original = source.cells[source_column]
      if original and not original.continuation then
        local source_width = math.min(math.max(1, original.width or 1), old_columns - source_column)
        local retained = last ~= nil and source_column <= last
        local width = retained and (source_width > new_columns and 1 or source_width) or 0
        for gap = source_column, math.min(old_columns, source_column + source_width) do
          gaps[gap] = length - base + math.min(gap - source_column, width)
        end
        if retained then
          if column > 0 and column + width > new_columns then
            segment.row.wrapped = true
            segment, column = start_segment(output, segments, logical, new_row, context, length)
          end
          local cell = copy_cell(original)
          cell.width = width
          if cell.continuation ~= nil then cell.continuation = nil end
          if cell.anchor_column ~= nil then cell.anchor_column = nil end
          segment.row.cells[column] = cell
          if width == 2 and column + 1 < new_columns then
            local continuation = copy_cell(cell)
            continuation.glyph, continuation.width, continuation.continuation, continuation.anchor_column = "", 0, true, column
            segment.row.cells[column + 1] = continuation
          end
          column, length = column + width, length + width
        end
      end
    end
    for gap = 0, old_columns do if gaps[gap] == nil then gaps[gap] = length - base end end
    offsets[source.line_id] = { base = base, gaps = gaps }
  end
  if blank_cell then
    for _, destination in ipairs(segments) do
      for gap = 0, new_columns - 1 do
        if destination.row.cells[gap] == nil then destination.row.cells[gap] = blank_cell(context) end
      end
    end
  end

  for _, source in ipairs(logical) do
    local source_offsets = offsets[source.line_id]
    local position = position_for(segments, source_offsets.base + source_offsets.gaps[0], new_columns)
    if compact_map then
      -- Keep numeric gap offsets and shared output segments. Resolve only
      -- positions actually requested by cursor/selection/shell metadata.
      map[source.line_id] = {
        base = source_offsets.base, gaps = source_offsets.gaps, segments = segments,
        old_columns = old_columns, new_columns = new_columns,
      }
    else
      local entries = {}
      for source_column = 0, old_columns do
        local mapped = position_for(segments, source_offsets.base + source_offsets.gaps[source_column], new_columns)
        entries[#entries + 1] = { column = mapped.column, line_id = mapped.line_id, source_column = source_column }
      end
      map[source.line_id] = entries
    end
    membership[source.line_id] = position.line_id
    for _, candidate in ipairs(segments) do
      if candidate.row.line_id == position.line_id then
        append_source(candidate.row, source.line_id)
        break
      end
    end
  end
end

-- Rewrap physical rows joined by their wrapped flag. `new_row` supplies a
-- row with a fresh line_id; the first resulting segment retains the
-- first source line_id. The returned map translates every old cell-gap
-- coordinate, including blank trailing cells. The membership table maps each
-- source row to the first output row that represents it, for row metadata.
-- Optional context is passed to factories and as the second is_blank argument.
function Reflow.transform(rows, old_columns, new_columns, new_row, is_blank, options)
  assert(type(rows) == "table" and old_columns >= 1 and new_columns >= 1, "invalid reflow input")
  assert(type(new_row) == "function", "reflow requires a row factory")
  is_blank = is_blank or default_blank
  local context = options and options.context
  local compact_map = options and options.compact_map == true
  local blank_cell = options and options.blank_cell
  assert(blank_cell == nil or type(blank_cell) == "function", "reflow blank-cell factory must be a function")

  local output, map, membership, logical = {}, {}, {}, {}
  for _, row in ipairs(rows) do
    logical[#logical + 1] = row
    if not row.wrapped then
      flush(logical, output, map, membership, old_columns, new_columns,
        new_row, is_blank, blank_cell, compact_map, context)
      logical = {}
    end
  end
  flush(logical, output, map, membership, old_columns, new_columns,
    new_row, is_blank, blank_cell, compact_map, context)
  return output, map, membership
end

function Reflow.remap_position(map, line_id, column, fallback)
  local entries = map[line_id]
  if entries and entries.gaps then
    local gap = math.max(0, math.min(entries.old_columns, math.floor(column)))
    return position_for(entries.segments, entries.base + entries.gaps[gap], entries.new_columns)
  end
  if entries == nil or #entries == 0 then return fallback end
  local selected = entries[1]
  for _, entry in ipairs(entries) do
    if entry.source_column > column then break end
    selected = entry
  end
  return { column = selected.column, line_id = selected.line_id }
end

return Reflow
