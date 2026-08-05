local Cell = require("terminal.cell")
local Config = require("terminal.config")
local Errors = require("runtime.errors")

local Row = {}
local row_mt = {}
row_mt.__index = row_mt

Row.contract = {
  clear_damage = "clear_damage()",
  copy = "copy(row) -> row | nil, error",
  delete = "delete(column, count, blank_cell) -> true | nil, error",
  dirty_range = "dirty_range() -> first_column, last_column | nil",
  erase = "erase(column, count, blank_cell) -> true | nil, error",
  get = "get(column) -> cell | nil, error",
  insert = "insert(column, count, blank_cell) -> true | nil, error",
  mark_all_dirty = "mark_all_dirty()",
  new = "new(columns) -> row | nil, error",
  replace = "replace(column, cell) -> true | nil, error",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function valid_column(row, column)
  if type(column) ~= "number" or column % 1 ~= 0 or column < 1 or column > row.columns then
    return config_error("column must be an integer within the row", { provided = column })
  end
  return column
end

local function clone_cell(cell)
  return Cell.new(cell)
end

local function mark_dirty(row, column)
  if row.dirty_first == nil or column < row.dirty_first then
    row.dirty_first = column
  end
  if row.dirty_last == nil or column > row.dirty_last then
    row.dirty_last = column
  end
end

local function mark_dirty_range(row, first, last)
  for column = first, last do
    mark_dirty(row, column)
  end
end

local function valid_count(count)
  if type(count) ~= "number" or count % 1 ~= 0 or count < 0 then
    return config_error("count must be a non-negative integer", { provided = count })
  end
  return count
end

local function blanks(row, first, last, blank_cell)
  for column = first, last do
    local blank, blank_error = clone_cell(blank_cell)
    if not blank then
      return nil, blank_error
    end
    row.cells[column] = blank
  end
  return true
end

function Row.new(columns)
  if columns == nil then
    return config_error("row columns must be provided")
  end
  local config, config_error_value = Config.new({ columns = columns })
  if not config then
    return nil, config_error_value
  end
  local cells = {}
  for column = 1, config.columns do
    local cell, cell_error = Cell.new()
    if not cell then
      return nil, cell_error
    end
    cells[column] = cell
  end
  return setmetatable({
    cells = cells,
    columns = config.columns,
    dirty_first = 1,
    dirty_last = config.columns,
    revision = 0,
    wrapped = false,
  }, row_mt)
end

function row_mt:get(column)
  local valid, column_error = valid_column(self, column)
  if not valid then
    return nil, column_error
  end
  return self.cells[valid]
end

function row_mt:replace(column, cell)
  local valid, column_error = valid_column(self, column)
  if not valid then
    return nil, column_error
  end
  local replacement, cell_error = clone_cell(cell)
  if not replacement then
    return nil, cell_error
  end
  self.cells[valid] = replacement
  self.revision = self.revision + 1
  mark_dirty(self, valid)
  return true
end

function row_mt:erase(column, count, blank_cell)
  local valid_column_value, column_error = valid_column(self, column)
  if not valid_column_value then
    return nil, column_error
  end
  local valid_count_value, count_error = valid_count(count)
  if not valid_count_value then
    return nil, count_error
  end
  local last = math.min(self.columns, valid_column_value + valid_count_value - 1)
  if last < valid_column_value then
    return true
  end
  local filled, fill_error = blanks(self, valid_column_value, last, blank_cell)
  if not filled then
    return nil, fill_error
  end
  self.revision = self.revision + 1
  mark_dirty_range(self, valid_column_value, last)
  return true
end

function row_mt:insert(column, count, blank_cell)
  local valid_column_value, column_error = valid_column(self, column)
  if not valid_column_value then
    return nil, column_error
  end
  local valid_count_value, count_error = valid_count(count)
  if not valid_count_value then
    return nil, count_error
  end
  local actual = math.min(valid_count_value, self.columns - valid_column_value + 1)
  if actual == 0 then
    return true
  end
  for destination = self.columns, valid_column_value + actual, -1 do
    self.cells[destination] = self.cells[destination - actual]
  end
  local filled, fill_error =
    blanks(self, valid_column_value, valid_column_value + actual - 1, blank_cell)
  if not filled then
    return nil, fill_error
  end
  self.revision = self.revision + 1
  mark_dirty_range(self, valid_column_value, self.columns)
  return true
end

function row_mt:delete(column, count, blank_cell)
  local valid_column_value, column_error = valid_column(self, column)
  if not valid_column_value then
    return nil, column_error
  end
  local valid_count_value, count_error = valid_count(count)
  if not valid_count_value then
    return nil, count_error
  end
  local actual = math.min(valid_count_value, self.columns - valid_column_value + 1)
  if actual == 0 then
    return true
  end
  for destination = valid_column_value, self.columns - actual do
    self.cells[destination] = self.cells[destination + actual]
  end
  local filled, fill_error = blanks(self, self.columns - actual + 1, self.columns, blank_cell)
  if not filled then
    return nil, fill_error
  end
  self.revision = self.revision + 1
  mark_dirty_range(self, valid_column_value, self.columns)
  return true
end

function row_mt:dirty_range()
  if self.dirty_first == nil then
    return nil
  end
  return self.dirty_first, self.dirty_last
end

function row_mt:clear_damage()
  self.dirty_first = nil
  self.dirty_last = nil
end

function row_mt:mark_all_dirty()
  self.dirty_first = 1
  self.dirty_last = self.columns
end

function Row.copy(row)
  if type(row) ~= "table" then
    return config_error("row must be a table")
  end
  if type(row.cells) ~= "table" then
    return config_error("row cells must be a table")
  end
  if type(row.revision) ~= "number" or row.revision % 1 ~= 0 or row.revision < 0 then
    return config_error("row revision must be a non-negative integer")
  end
  local copy, copy_error = Row.new(row.columns)
  if not copy then
    return nil, copy_error
  end
  if type(row.wrapped) ~= "boolean" then
    return config_error("row wrapped state must be a boolean")
  end
  for column = 1, copy.columns do
    if row.cells[column] == nil then
      return config_error("row is missing a cell", { column = column })
    end
    local replacement, replacement_error = copy:replace(column, row.cells[column])
    if not replacement then
      return nil, replacement_error
    end
  end
  copy.revision = row.revision
  copy.wrapped = row.wrapped
  copy:clear_damage()
  return copy
end

return Row
