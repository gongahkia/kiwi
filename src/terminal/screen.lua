local Config = require("terminal.config")
local Errors = require("runtime.errors")
local Row = require("terminal.row")

local Screen = {}
local screen_mt = {}
screen_mt.__index = screen_mt

Screen.contract = {
  clear_damage = "clear_damage()",
  delete_lines = "delete_lines(row, count, top, bottom, blank_cell) -> removed_rows | nil, error",
  insert_lines = "insert_lines(row, count, top, bottom, blank_cell) -> removed_rows | nil, error",
  new = "new(columns, rows) -> screen | nil, error",
  row = "row(index) -> row | nil, error",
  scroll_down = "scroll_down(top, bottom, count, blank_cell) -> displaced_rows | nil, error",
  scroll_up = "scroll_up(top, bottom) -> displaced_row | nil, error",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function valid_index(screen, index)
  if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > screen.height then
    return config_error("row index must be an integer within the screen", { provided = index })
  end
  return index
end

local function valid_count(count)
  if type(count) ~= "number" or count % 1 ~= 0 or count < 0 then
    return config_error("count must be a non-negative integer", { provided = count })
  end
  return count
end

local function valid_region(screen, top, bottom)
  local valid_top, top_error = valid_index(screen, top)
  if not valid_top then
    return nil, nil, top_error
  end
  local valid_bottom, bottom_error = valid_index(screen, bottom)
  if not valid_bottom then
    return nil, nil, bottom_error
  end
  if valid_top > valid_bottom then
    local _, region_error = config_error("scroll region top must not exceed bottom")
    return nil, nil, region_error
  end
  return valid_top, valid_bottom
end

local function blank_row(screen, blank_cell)
  local row, row_error = Row.new(screen.columns)
  if not row then
    return nil, row_error
  end
  if blank_cell ~= nil then
    local erased, erase_error = row:erase(1, screen.columns, blank_cell)
    if not erased then
      return nil, erase_error
    end
  end
  return row
end

local function mark_region_dirty(screen, top, bottom)
  for index = top, bottom do
    screen.rows[index]:mark_all_dirty()
  end
end

function Screen.new(columns, rows)
  if columns == nil or rows == nil then
    return config_error("screen columns and rows must be provided")
  end
  local config, config_error_value = Config.new({ columns = columns, rows = rows })
  if not config then
    return nil, config_error_value
  end
  local visible_rows = {}
  for index = 1, config.rows do
    local row, row_error = Row.new(config.columns)
    if not row then
      return nil, row_error
    end
    visible_rows[index] = row
  end
  return setmetatable({
    columns = config.columns,
    height = config.rows,
    rows = visible_rows,
  }, screen_mt)
end

function screen_mt:row(index)
  local valid, index_error = valid_index(self, index)
  if not valid then
    return nil, index_error
  end
  return self.rows[valid]
end

function screen_mt:clear_damage()
  for _, row in ipairs(self.rows) do
    row:clear_damage()
  end
end

function screen_mt:scroll_up(top, bottom, blank_cell)
  local valid_top, valid_bottom, region_error = valid_region(self, top, bottom)
  if not valid_top then
    return nil, region_error
  end
  local displaced = self.rows[valid_top]
  for index = valid_top, valid_bottom - 1 do
    self.rows[index] = self.rows[index + 1]
  end
  local blank, blank_error = blank_row(self, blank_cell)
  if not blank then
    return nil, blank_error
  end
  self.rows[valid_bottom] = blank
  mark_region_dirty(self, valid_top, valid_bottom)
  return displaced
end

function screen_mt:scroll_down(top, bottom, count, blank_cell)
  local valid_top, valid_bottom, region_error = valid_region(self, top, bottom)
  if not valid_top then
    return nil, region_error
  end
  local valid_count_value, count_error = valid_count(count)
  if not valid_count_value then
    return nil, count_error
  end
  local actual = math.min(valid_count_value, valid_bottom - valid_top + 1)
  local displaced = {}
  for _ = 1, actual do
    displaced[#displaced + 1] = self.rows[valid_bottom]
    for index = valid_bottom, valid_top + 1, -1 do
      self.rows[index] = self.rows[index - 1]
    end
    local blank, blank_error = blank_row(self, blank_cell)
    if not blank then
      return nil, blank_error
    end
    self.rows[valid_top] = blank
  end
  if actual > 0 then
    mark_region_dirty(self, valid_top, valid_bottom)
  end
  return displaced
end

function screen_mt:insert_lines(row, count, top, bottom, blank_cell)
  local valid_top, valid_bottom, region_error = valid_region(self, top, bottom)
  if not valid_top then
    return nil, region_error
  end
  local valid_row, row_error = valid_index(self, row)
  if not valid_row then
    return nil, row_error
  end
  if valid_row < valid_top or valid_row > valid_bottom then
    return {}
  end
  local valid_count_value, count_error = valid_count(count)
  if not valid_count_value then
    return nil, count_error
  end
  local actual = math.min(valid_count_value, valid_bottom - valid_row + 1)
  return self:scroll_down(valid_row, valid_bottom, actual, blank_cell)
end

function screen_mt:delete_lines(row, count, top, bottom, blank_cell)
  local valid_top, valid_bottom, region_error = valid_region(self, top, bottom)
  if not valid_top then
    return nil, region_error
  end
  local valid_row, row_error = valid_index(self, row)
  if not valid_row then
    return nil, row_error
  end
  local valid_count_value, count_error = valid_count(count)
  if not valid_count_value then
    return nil, count_error
  end
  if valid_row < valid_top or valid_row > valid_bottom then
    return {}
  end
  local actual = math.min(valid_count_value, valid_bottom - valid_row + 1)
  local removed = {}
  for _ = 1, actual do
    removed[#removed + 1] = self.rows[valid_row]
    for index = valid_row, valid_bottom - 1 do
      self.rows[index] = self.rows[index + 1]
    end
    local blank, blank_error = blank_row(self, blank_cell)
    if not blank then
      return nil, blank_error
    end
    self.rows[valid_bottom] = blank
  end
  if actual > 0 then
    mark_region_dirty(self, valid_row, valid_bottom)
  end
  return removed
end

return Screen
