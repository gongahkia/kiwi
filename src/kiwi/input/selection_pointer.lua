local SelectionPointer = {}
SelectionPointer.__index = SelectionPointer

local double_click_seconds = 0.4
local click_distance = 4

local function clamp(value, lower, upper)
  return math.max(lower, math.min(value, upper))
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function application_mouse_enabled(modes)
  return modes and modes.mouse_sgr == true and (modes.mouse_tracking == "normal" or modes.mouse_tracking == "button" or modes.mouse_tracking == "any")
end

function SelectionPointer.new()
  return setmetatable({ drag = nil, last_click = nil }, SelectionPointer)
end

function SelectionPointer:reset()
  self.drag = nil
  self.last_click = nil
end

function SelectionPointer.cell_position(x, y, content_scale, cell_width, cell_height, columns, rows)
  assert(finite(x) and finite(y) and finite(content_scale) and finite(cell_width) and finite(cell_height), "pointer position must be finite")
  assert(content_scale > 0 and cell_width > 0 and cell_height > 0 and columns > 0 and rows > 0, "pointer cell geometry must be positive")
  return clamp(math.floor(x * content_scale / cell_width), 0, columns - 1), clamp(math.floor(y * content_scale / cell_height), 0, rows - 1)
end

function SelectionPointer:next_click(event)
  local previous = self.last_click
  local count = 1
  if previous and event.time - previous.time <= double_click_seconds
    and math.abs(event.x - previous.x) <= click_distance
    and math.abs(event.y - previous.y) <= click_distance then
    count = previous.count < 3 and previous.count + 1 or 1
  end
  self.last_click = { count = count, time = event.time, x = event.x, y = event.y }
  return count
end

function SelectionPointer:update_drag(state, row, column)
  local drag = self.drag
  local target = state:selection_cell_bounds(row, column)
  if target.row == drag.row and target.start == drag.start then return false end
  if state:selection_precedes(target.row, target.start, drag.row, drag.start) then
    state:set_selection(drag.row, drag.finish, target.row, target.start)
  else
    state:set_selection(drag.row, drag.start, target.row, target.finish)
  end
  return true
end

function SelectionPointer:handle(event, state, modes)
  if application_mouse_enabled(modes) then
    self.drag = nil
    return false, false
  end
  if event.kind == "motion" then
    if self.drag == nil then return false, false end
    return true, self:update_drag(state, event.selection_row, event.selection_column)
  end
  if event.kind ~= "button" or event.button ~= 0 then return false, false end
  if event.action == "release" then
    if self.drag == nil then return false, false end
    local changed = self:update_drag(state, event.selection_row, event.selection_column)
    self.drag = nil
    return true, changed
  end
  if event.action ~= "press" then return false, false end
  local clicks = self:next_click(event)
  if clicks == 3 then
    state:set_selection(event.selection_row, 0, event.selection_row, state.columns)
    self.drag = nil
  elseif clicks == 2 then
    local word = state:selection_word_bounds(event.selection_row, event.selection_column)
    state:set_selection(word.row, word.start, word.row, word.finish)
    self.drag = nil
  else
    local cell = state:selection_cell_bounds(event.selection_row, event.selection_column)
    state:set_selection(cell.row, cell.start, cell.row, cell.start)
    self.drag = { finish = cell.finish, row = cell.row, start = cell.start }
  end
  return true, true
end

return SelectionPointer
