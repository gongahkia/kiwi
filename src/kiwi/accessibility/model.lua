local Model = {}
Model.__index = Model

local function clamp(value, lower, upper)
  return math.max(lower, math.min(value, upper))
end

local function copy_endpoint(endpoint)
  if endpoint == nil then return nil end
  return { line_id = endpoint.line_id, column = endpoint.column }
end

local function same_endpoint(left, right)
  return left == right or (left and right and left.line_id == right.line_id and left.column == right.column)
end

local function same_selection(left, right)
  return left.active == right.active
    and left.empty == right.empty
    and left.visible == right.visible
    and left.scope == right.scope
    and same_endpoint(left.start, right.start)
    and same_endpoint(left.finish, right.finish)
end

local function same_caret(left, right)
  return left.scope == right.scope
    and left.line_id == right.line_id
    and left.column == right.column
    and left.row == right.row
    and left.visible == right.visible
end

local function same_viewport(left, right)
  return left.scope == right.scope
    and left.history_offset == right.history_offset
    and left.columns == right.columns
    and left.rows == right.rows
    and left.start_row == right.start_row
    and left.exported_rows == right.exported_rows
    and left.omitted_rows == right.omitted_rows
    and left.first_line_id == right.first_line_id
    and left.last_line_id == right.last_line_id
end

local function rows_equal(left, right)
  if #left ~= #right then return false end
  for index, row in ipairs(left) do
    local other = right[index]
    if row.line_id ~= other.line_id or row.text ~= other.text or row.start_column ~= other.start_column or row.finish_column ~= other.finish_column or row.truncated ~= other.truncated then return false end
  end
  return true
end

local function selection_view(state)
  local view = state:selection_view()
  return {
    active = view.active == true,
    empty = view.empty == true,
    visible = view.visible == true,
    scope = view.scope,
    start = copy_endpoint(view.start),
    finish = copy_endpoint(view.finish),
  }
end

function Model.new(options)
  options = options or {}
  local max_rows = options.max_rows or 256
  local max_bytes = options.max_bytes or 65536
  assert(type(max_rows) == "number" and max_rows >= 1 and max_rows % 1 == 0, "accessibility max_rows must be a positive integer")
  assert(type(max_bytes) == "number" and max_bytes >= 1 and max_bytes % 1 == 0, "accessibility max_bytes must be a positive integer")
  return setmetatable({ max_rows = max_rows, max_bytes = max_bytes, previous = nil }, Model)
end

function Model:caret(state)
  local cursor = state.active_screen.cursor
  local row = state.active_screen.rows[cursor.row]
  return {
    scope = state:selection_scope(),
    line_id = row.line_id,
    column = cursor.column,
    row = cursor.row,
    visible = cursor.visible == true,
  }
end

function Model:selection(state)
  return selection_view(state)
end

function Model:viewport(state)
  local exported_rows = math.min(state.rows, self.max_rows)
  local start_row = clamp(state.active_screen.cursor.row - math.floor(exported_rows / 2), 0, state.rows - exported_rows)
  local first = state:visible_row(start_row)
  local last = state:visible_row(start_row + exported_rows - 1)
  return {
    scope = state:selection_scope(),
    history_offset = state.history_offset,
    columns = state.columns,
    rows = state.rows,
    start_row = start_row,
    exported_rows = exported_rows,
    omitted_rows = state.rows - exported_rows,
    first_line_id = first.line_id,
    last_line_id = last.line_id,
  }
end

function Model:visible_text(state, viewport)
  viewport = viewport or self:viewport(state)
  local remaining = self.max_bytes
  local rows = {}
  for row_index = viewport.start_row, viewport.start_row + viewport.exported_rows - 1 do
    if remaining == 0 then break end
    local source = state:visible_row(row_index)
    local text = {}
    local bytes = 0
    local truncated = false
    for column = 0, state.columns - 1 do
      local cell = source.cells[column]
      if not cell.continuation then
        local glyph = cell.glyph or ""
        if #glyph > remaining then
          truncated = true
          break
        end
        text[#text + 1] = glyph
        bytes = bytes + #glyph
        remaining = remaining - #glyph
      end
    end
    rows[#rows + 1] = {
      line_id = source.line_id,
      row = row_index,
      start_column = 0,
      finish_column = state.columns,
      text = table.concat(text),
      wrapped = source.wrapped == true,
      truncated = truncated,
    }
    if truncated or remaining == 0 then break end
  end
  return rows, remaining == 0
end

function Model:range_at(state, row, column)
  assert(type(row) == "number" and row >= 0 and row < state.rows and row % 1 == 0, "accessible row is out of bounds")
  assert(type(column) == "number" and column >= 0 and column < state.columns and column % 1 == 0, "accessible column is out of bounds")
  local source = state:visible_row(row)
  local cell = source.cells[column]
  if cell.continuation then column = cell.anchor_column end
  local anchor = source.cells[column]
  return {
    scope = state:selection_scope(),
    line_id = source.line_id,
    start_column = column,
    finish_column = column + (anchor.width == 2 and 2 or 1),
    text = anchor.glyph or "",
  }
end

function Model:snapshot(state)
  local viewport = self:viewport(state)
  local rows, text_truncated = self:visible_text(state, viewport)
  return {
    version = 1,
    viewport = viewport,
    caret = self:caret(state),
    selection = self:selection(state),
    text = {
      rows = rows,
      truncated = text_truncated or #rows < viewport.exported_rows,
      maximum_bytes = self.max_bytes,
    },
  }
end

function Model:poll(state)
  local current = self:snapshot(state)
  local previous = self.previous
  self.previous = current
  if previous == nil then
    return current, { { kind = "initial", viewport = current.viewport, caret = current.caret, selection = current.selection } }
  end
  local events = {}
  if previous.viewport.columns ~= current.viewport.columns or previous.viewport.rows ~= current.viewport.rows then
    events[#events + 1] = { kind = "resize", viewport = current.viewport }
  end
  if not same_viewport(previous.viewport, current.viewport) then
    events[#events + 1] = { kind = "viewport", viewport = current.viewport }
  end
  if not rows_equal(previous.text.rows, current.text.rows) or previous.text.truncated ~= current.text.truncated then
    events[#events + 1] = { kind = "output", viewport = current.viewport, text_truncated = current.text.truncated }
  end
  if not same_caret(previous.caret, current.caret) then
    events[#events + 1] = { kind = "caret", caret = current.caret }
  end
  if not same_selection(previous.selection, current.selection) then
    events[#events + 1] = { kind = "selection", selection = current.selection }
  end
  return current, events
end

return Model
