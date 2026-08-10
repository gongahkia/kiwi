local Selection = {}
Selection.__index = Selection

local function clamp(value, lower, upper)
  return math.max(lower, math.min(value, upper))
end

local function copy_endpoint(endpoint)
  return { column = endpoint.column, line_id = endpoint.line_id }
end

local function positions_for(document)
  local positions = {}
  for index, entry in ipairs(document) do
    positions[entry.line_id] = index
  end
  return positions
end

local function compare(left, right, positions)
  local left_index = positions[left.line_id]
  local right_index = positions[right.line_id]
  if left_index ~= right_index then return left_index < right_index and -1 or 1 end
  if left.column == right.column then return 0 end
  return left.column < right.column and -1 or 1
end

local function clamp_endpoint(endpoint, document, positions, columns)
  local index = positions[endpoint.line_id]
  if index == nil then return nil end
  return { column = clamp(endpoint.column, 0, columns), line_id = document[index].line_id }
end

local function snap(row, column, columns, toward_end)
  if column <= 0 or column >= columns then return column end
  local cell = row.cells[column]
  if not cell or not cell.continuation then return column end
  local anchor_column = cell.anchor_column
  local anchor = type(anchor_column) == "number" and row.cells[anchor_column] or nil
  if not anchor then return column end
  if toward_end then return math.min(columns, anchor_column + math.max(1, anchor.width or 1)) end
  return anchor_column
end

function Selection.new()
  return setmetatable({ anchor = nil, focus = nil, scope = nil }, Selection)
end

function Selection:clear()
  self.anchor = nil
  self.focus = nil
  self.scope = nil
end

function Selection:reconcile(document, columns)
  if self.anchor == nil or self.focus == nil then return false end
  local positions = positions_for(document)
  local anchor = clamp_endpoint(self.anchor, document, positions, columns)
  local focus = clamp_endpoint(self.focus, document, positions, columns)
  if anchor == nil or focus == nil then
    self:clear()
    return false
  end
  local anchor_index = positions[anchor.line_id]
  local focus_index = positions[focus.line_id]
  if compare(anchor, focus, positions) <= 0 then
    anchor.column = snap(document[anchor_index].row, anchor.column, columns, false)
    focus.column = snap(document[focus_index].row, focus.column, columns, true)
  else
    anchor.column = snap(document[anchor_index].row, anchor.column, columns, true)
    focus.column = snap(document[focus_index].row, focus.column, columns, false)
  end
  self.anchor = anchor
  self.focus = focus
  return true
end

function Selection:set(scope, anchor, focus, document, columns)
  self.scope = scope
  self.anchor = copy_endpoint(anchor)
  self.focus = copy_endpoint(focus)
  return self:reconcile(document, columns)
end

function Selection:view(document, columns, visible_scope)
  if not self:reconcile(document, columns) then
    return { active = false, empty = true, visible = false }
  end
  local positions = positions_for(document)
  local start, finish
  if compare(self.anchor, self.focus, positions) <= 0 then
    start, finish = self.anchor, self.focus
  else
    start, finish = self.focus, self.anchor
  end
  return {
    active = true,
    anchor = copy_endpoint(self.anchor),
    empty = start.line_id == finish.line_id and start.column == finish.column,
    finish = copy_endpoint(finish),
    focus = copy_endpoint(self.focus),
    scope = self.scope,
    start = copy_endpoint(start),
    visible = self.scope == visible_scope,
  }
end

return Selection
