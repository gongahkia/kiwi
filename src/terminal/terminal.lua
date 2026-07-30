local Errors = require("runtime.errors")
local Config = require("terminal.config")
local Cursor = require("terminal.cursor")
local Rendition = require("terminal.rendition")
local Scrollback = require("terminal.scrollback")
local Screen = require("terminal.screen")

local Terminal = {}
local terminal_mt = {}
terminal_mt.__index = terminal_mt

local function default_tab_stops(columns)
  local tab_stops = {}
  for column = 9, columns, 8 do
    tab_stops[column] = true
  end
  return tab_stops
end

Terminal.contract = {
  constructor = "new(config) -> terminal | nil, error",
  start = "start() -> nil, error",
  feed_output = "feed_output(bytes) -> nil, error",
  resize = "resize(columns, rows) -> nil, error",
  snapshot = "snapshot() -> nil, error",
  destroy = "destroy()",
}

function Terminal.new(config)
  if type(config) ~= "table" then
    return nil, Errors.new("config_error", "terminal config must be a table")
  end
  local terminal_config, config_error = Config.new(config)
  if not terminal_config then
    return nil, config_error
  end
  local cursor, cursor_error = Cursor.new()
  if not cursor then
    return nil, cursor_error
  end
  local saved_cursor, saved_cursor_error = Cursor.copy(cursor)
  if not saved_cursor then
    return nil, saved_cursor_error
  end
  local rendition, rendition_error = Rendition.new()
  if not rendition then
    return nil, rendition_error
  end
  local scrollback, scrollback_error = Scrollback.new(terminal_config.scrollback_limit)
  if not scrollback then
    return nil, scrollback_error
  end
  local primary_screen, primary_error = Screen.new(terminal_config.columns, terminal_config.rows)
  if not primary_screen then
    return nil, primary_error
  end
  local alternate_screen, alternate_error =
    Screen.new(terminal_config.columns, terminal_config.rows)
  if not alternate_screen then
    return nil, alternate_error
  end
  return setmetatable({
    active_buffer = "primary",
    alternate_screen = alternate_screen,
    config = terminal_config,
    cursor = cursor,
    margins = { bottom = terminal_config.rows, top = 1 },
    primary_screen = primary_screen,
    rendition = rendition,
    saved_cursor = saved_cursor,
    scrollback = scrollback,
    state = "bootstrap",
    tab_stops = default_tab_stops(terminal_config.columns),
  }, terminal_mt)
end

function terminal_mt:start()
  return nil, Errors.new("internal_invariant_error", "terminal start is not implemented")
end

function terminal_mt:feed_output(bytes)
  if type(bytes) ~= "string" then
    return nil, Errors.new("config_error", "terminal output must be bytes")
  end
  return nil, Errors.new("internal_invariant_error", "terminal parser is not implemented")
end

function terminal_mt:resize(columns, rows)
  if type(columns) ~= "number" or type(rows) ~= "number" then
    return nil, Errors.new("config_error", "terminal dimensions must be numbers")
  end
  return nil, Errors.new("internal_invariant_error", "terminal resize is not implemented")
end

function terminal_mt:snapshot()
  return nil, Errors.new("internal_invariant_error", "terminal snapshot is not implemented")
end

function terminal_mt:destroy()
  self.state = "destroyed"
end

return Terminal
