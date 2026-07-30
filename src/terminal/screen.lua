local Config = require("terminal.config")
local Errors = require("runtime.errors")
local Row = require("terminal.row")

local Screen = {}
local screen_mt = {}
screen_mt.__index = screen_mt

Screen.contract = {
  clear_damage = "clear_damage()",
  new = "new(columns, rows) -> screen | nil, error",
  row = "row(index) -> row | nil, error",
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

function screen_mt:scroll_up(top, bottom)
  local valid_top, top_error = valid_index(self, top)
  if not valid_top then
    return nil, top_error
  end
  local valid_bottom, bottom_error = valid_index(self, bottom)
  if not valid_bottom then
    return nil, bottom_error
  end
  if valid_top > valid_bottom then
    return config_error("scroll region top must not exceed bottom")
  end
  local displaced = self.rows[valid_top]
  for index = valid_top, valid_bottom - 1 do
    self.rows[index] = self.rows[index + 1]
  end
  local blank, blank_error = Row.new(self.columns)
  if not blank then
    return nil, blank_error
  end
  self.rows[valid_bottom] = blank
  for index = valid_top, valid_bottom do
    self.rows[index]:mark_all_dirty()
  end
  return displaced
end

return Screen
