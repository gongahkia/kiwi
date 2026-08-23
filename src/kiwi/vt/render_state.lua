local RenderState = {}
RenderState.__index = RenderState
RenderState.api_version = 1

local function copy_range(range)
  return { count = range.count, first = range.first }
end

local function copy_cell(state, cell)
  local foreground, background = cell.fg, cell.bg
  if state.presentation_colors then foreground, background = state:presentation_colors(cell) end
  local copy = {
    anchor_column = cell.anchor_column,
    bg = background,
    continuation = cell.continuation == true,
    display_text = cell.display_text,
    fg = foreground,
    flags = cell.flags,
    glyph = cell.glyph,
    hyperlink_id = cell.hyperlink_id,
    width = cell.width,
  }
  if cell.codepoints then
    copy.codepoints = {}
    for index, codepoint in ipairs(cell.codepoints) do copy.codepoints[index] = codepoint end
  end
  return copy
end

local function copy_damage(damage)
  local ranges = {}
  for index, range in ipairs(damage:ranges()) do ranges[index] = copy_range(range) end
  return {
    cells = damage.dirty_count,
    full = damage.full,
    ranges = ranges,
  }
end

local function copy_endpoint(endpoint)
  if endpoint == nil then return nil end
  return { column = endpoint.column, line_id = endpoint.line_id }
end

local function selection_view(state)
  local selection = state:selection_view()
  return {
    active = selection.active == true,
    empty = selection.empty == true,
    finish = copy_endpoint(selection.finish),
    scope = selection.scope,
    start = copy_endpoint(selection.start),
    visible = selection.visible == true,
  }
end

local function input_modes(state)
  return state:input_modes()
end

-- The view is deliberately single-threaded: its cells are borrowed from the
-- terminal for the begin/end update interval. Consumers must finish the
-- update before mutating the terminal through the public facade.
local function new_view(owner, state)
  local view = {
    active_screen = state.active_screen == state.primary and "primary" or "alternate",
    columns = state.columns,
    cursor = {
      column = state.cursor.column,
      pending_wrap = state.cursor.pending_wrap == true,
      row = state.cursor.row,
      visible = state.cursor.visible == true,
    },
    damage = copy_damage(state.damage),
    generation = owner.generation,
    input_modes = input_modes(state),
    rows = state.rows,
    selection = selection_view(state),
  }

  function view:cell(column, row)
    assert(type(column) == "number" and column % 1 == 0 and column >= 0 and column < self.columns, "render-state column is out of bounds")
    assert(type(row) == "number" and row % 1 == 0 and row >= 0 and row < self.rows, "render-state row is out of bounds")
    return copy_cell(state, state:get(column, row))
  end

  function view:row(row)
    assert(type(row) == "number" and row % 1 == 0 and row >= 0 and row < self.rows, "render-state row is out of bounds")
    local cells = {}
    for column = 0, self.columns - 1 do cells[column + 1] = copy_cell(state, state:get(column, row)) end
    return cells
  end

  return view
end

function RenderState.new(state)
  assert(type(state) == "table" and type(state.get) == "function", "render state needs a terminal state")
  return setmetatable({ active = false, generation = 0, state = state, view = nil }, RenderState)
end

function RenderState:begin_update()
  assert(not self.active, "render-state update is already active")
  self.active = true
  self.generation = self.generation + 1
  self.view = new_view(self, self.state)
  return self.view
end

function RenderState:end_update(consumed)
  assert(self.active, "render-state update is not active")
  self.active = false
  self.view = nil
  if consumed then self.state.damage:clear() end
end

return RenderState
