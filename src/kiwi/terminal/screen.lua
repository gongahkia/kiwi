local Cell = require("kiwi.terminal.cell")
local Screen = {}
Screen.__index = Screen

local copy_cell = Cell.copy_into

local function new_row(columns, blank_cell, line_id_factory, owner, cells)
  if cells then
    local blank = blank_cell(owner)
    for column = 0, columns - 1 do copy_cell(cells[column], blank) end
  else
    cells = {}
    for column = 0, columns - 1 do cells[column] = blank_cell(owner) end
  end
  return { cells = cells, command_region_ids = nil, command_regions_truncated = false, line_id = line_id_factory and line_id_factory(owner) or nil, wrapped = false }
end

function Screen.new(columns, rows, blank_cell, line_id_factory, owner)
  local self = setmetatable({
    columns = columns,
    rows_count = rows,
    blank_cell = blank_cell,
    owner = owner,
    line_id_factory = line_id_factory,
    rows = {},
    cursor = { column = 0, row = 0, visible = true, pending_wrap = false },
    saved_cursor = { column = 0, row = 0 },
    keyboard_flags = 0,
    keyboard_stack = {},
    hyperlink_id = nil,
    attributes = nil,
    top_margin = 0,
    bottom_margin = rows - 1,
    left_margin = 0,
    right_margin = columns - 1,
  }, Screen)
  for row = 0, rows - 1 do
    self.rows[row] = new_row(columns, blank_cell, line_id_factory, owner)
  end
  return self
end

function Screen:new_row(cells)
  return new_row(self.columns, self.blank_cell, self.line_id_factory, self.owner, cells)
end

-- Reflow fills text first and allocates only the remaining blank cells.
function Screen:new_sparse_row()
  return new_row(0, self.blank_cell, self.line_id_factory, self.owner)
end

function Screen:get(column, row)
  return self.rows[row].cells[column]
end

function Screen:clear_row(row, cell_factory)
  local target = self.rows[row]
  for column = 0, self.columns - 1 do
    copy_cell(target.cells[column], cell_factory())
  end
  target.wrapped = false
end

function Screen:resize(columns, rows, blank_cell)
  local resized = Screen.new(columns, rows, blank_cell, self.line_id_factory, self.owner)
  local rows_to_copy = math.min(self.rows_count, rows)
  local columns_to_copy = math.min(self.columns, columns)
  for row = 0, rows_to_copy - 1 do
    for column = 0, columns_to_copy - 1 do
      copy_cell(resized.rows[row].cells[column], self.rows[row].cells[column])
    end
    resized.rows[row].line_id = self.rows[row].line_id
    if self.rows[row].command_region_ids then
      local ids = {}
      for index, id in ipairs(self.rows[row].command_region_ids) do ids[index] = id end
      resized.rows[row].command_region_ids = ids
    end
    if self.rows[row].kitty_placement_ids then
      local ids = {}
      for index, id in ipairs(self.rows[row].kitty_placement_ids) do ids[index] = id end
      resized.rows[row].kitty_placement_ids = ids
    end
    resized.rows[row].command_regions_truncated = self.rows[row].command_regions_truncated
    resized.rows[row].wrapped = self.rows[row].wrapped
  end
  resized.cursor.column = math.min(self.cursor.column, columns - 1)
  resized.cursor.row = math.min(self.cursor.row, rows - 1)
  resized.cursor.visible = self.cursor.visible
  resized.saved_cursor.column = math.min(self.saved_cursor.column, columns - 1)
  resized.saved_cursor.row = math.min(self.saved_cursor.row, rows - 1)
  resized.saved_cursor.hyperlink_id = self.saved_cursor.hyperlink_id
  resized.saved_cursor.attributes = self.saved_cursor.attributes
  if self.saved_cursor.character_sets then
    resized.saved_cursor.character_sets = {
      g0 = self.saved_cursor.character_sets.g0,
      g1 = self.saved_cursor.character_sets.g1,
      gl = self.saved_cursor.character_sets.gl,
    }
  end
  resized.keyboard_flags = self.keyboard_flags
  for index, flags in ipairs(self.keyboard_stack) do
    resized.keyboard_stack[index] = flags
  end
  resized.attributes = self.attributes
  resized.hyperlink_id = self.hyperlink_id
  return resized
end

function Screen:scroll_up(top, bottom, count, preserve_row, discard_row)
  for _ = 1, count do
    local outgoing = self.rows[top]
    local cells
    if preserve_row then
      -- The preserver may return a detached cell array. A nil return retains
      -- the original ownership contract and allocates a fresh screen row.
      cells = preserve_row(outgoing)
    else
      if discard_row then discard_row(outgoing) end
      cells = outgoing.cells
    end
    for row = top, bottom - 1 do
      self.rows[row] = self.rows[row + 1]
    end
    self.rows[bottom] = self:new_row(cells)
  end
end

function Screen:scroll_down(top, bottom, count, discard_row)
  for _ = 1, count do
    local outgoing = self.rows[bottom]
    if discard_row then discard_row(outgoing) end
    for row = bottom, top + 1, -1 do
      self.rows[row] = self.rows[row - 1]
    end
    self.rows[top] = self:new_row(outgoing.cells)
  end
end

function Screen:scroll_rect_up(top, bottom, left, right, count, cell_factory)
  for _ = 1, count do
    for row = top, bottom - 1 do
      for column = left, right do
        copy_cell(self.rows[row].cells[column], self.rows[row + 1].cells[column])
      end
    end
    for column = left, right do
      copy_cell(self.rows[bottom].cells[column], cell_factory())
    end
  end
end

function Screen:scroll_rect_down(top, bottom, left, right, count, cell_factory)
  for _ = 1, count do
    for row = bottom, top + 1, -1 do
      for column = left, right do
        copy_cell(self.rows[row].cells[column], self.rows[row - 1].cells[column])
      end
    end
    for column = left, right do
      copy_cell(self.rows[top].cells[column], cell_factory())
    end
  end
end

return Screen
