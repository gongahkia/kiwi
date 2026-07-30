local Errors = require("runtime.errors")
local Config = require("terminal.config")
local Cell = require("terminal.cell")
local Cursor = require("terminal.cursor")
local Digest = require("terminal.digest")
local Parser = require("terminal.parser")
local Rendition = require("terminal.rendition")
local Scrollback = require("terminal.scrollback")
local Screen = require("terminal.screen")
local Utf8 = require("terminal.utf8")

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
  digest = "digest() -> canonical_digest | nil, error",
  start = "start() -> nil, error",
  feed_output = "feed_output(bytes) -> semantic_events | nil, error",
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
  local parser, parser_error = Parser.new()
  if not parser then
    return nil, parser_error
  end
  local utf8_decoder = Utf8.new()
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
    parser = parser,
    primary_screen = primary_screen,
    rendition = rendition,
    saved_cursor = saved_cursor,
    scrollback = scrollback,
    state = "bootstrap",
    tab_stops = default_tab_stops(terminal_config.columns),
    utf8_decoder = utf8_decoder,
  }, terminal_mt)
end

function terminal_mt:start()
  return nil, Errors.new("internal_invariant_error", "terminal start is not implemented")
end

function terminal_mt:digest()
  return Digest.terminal(self)
end

local function active_screen(terminal)
  if terminal.active_buffer == "primary" then
    return terminal.primary_screen
  end
  return terminal.alternate_screen
end

local function cursor_event(terminal, events, offset)
  events[#events + 1] = {
    column = terminal.cursor.column,
    kind = "cursor_moved",
    offset = offset,
    row = terminal.cursor.row,
  }
end

local function line_feed(terminal, events, offset, byte)
  local cursor = terminal.cursor
  if cursor.row < terminal.margins.bottom then
    cursor.row = cursor.row + 1
    cursor.pending_wrap = false
    cursor_event(terminal, events, offset)
    return true
  end
  local screen = active_screen(terminal)
  local displaced, scroll_error = screen:scroll_up(terminal.margins.top, terminal.margins.bottom)
  if not displaced then
    return nil, scroll_error
  end
  if terminal.active_buffer == "primary" and terminal.margins.top == 1 then
    local pushed, push_error = terminal.scrollback:push(displaced)
    if not pushed then
      return nil, push_error
    end
  end
  cursor.pending_wrap = false
  events[#events + 1] = {
    byte = byte,
    kind = "scrolled",
    offset = offset,
    top = terminal.margins.top,
    bottom = terminal.margins.bottom,
  }
  return true
end

local function apply_control(terminal, events, event)
  local cursor = terminal.cursor
  if event.byte == 0x00 then
    return true
  end
  if event.byte == 0x07 then
    events[#events + 1] = { kind = "bell", offset = event.offset }
    return true
  end
  if event.byte == 0x08 then
    cursor.pending_wrap = false
    if cursor.column > 1 then
      cursor.column = cursor.column - 1
      cursor_event(terminal, events, event.offset)
    end
    return true
  end
  if event.byte == 0x09 then
    cursor.pending_wrap = false
    local target = terminal.config.columns
    for column = cursor.column + 1, terminal.config.columns do
      if terminal.tab_stops[column] then
        target = column
        break
      end
    end
    if target ~= cursor.column then
      cursor.column = target
      cursor_event(terminal, events, event.offset)
    end
    return true
  end
  if event.byte == 0x0A or event.byte == 0x0B or event.byte == 0x0C then
    return line_feed(terminal, events, event.offset, event.byte)
  end
  if event.byte == 0x0D then
    cursor.pending_wrap = false
    if cursor.column ~= 1 then
      cursor.column = 1
      cursor_event(terminal, events, event.offset)
    end
  end
  return true
end

local function write_printable(terminal, events, offset, byte, text)
  local cursor = terminal.cursor
  if cursor.pending_wrap then
    local advanced, advance_error = line_feed(terminal, events, offset, nil)
    if not advanced then
      return nil, advance_error
    end
    cursor.column = 1
  end
  local cell, cell_error = Cell.new({
    attributes = terminal.rendition.attributes,
    background = terminal.rendition.background,
    foreground = terminal.rendition.foreground,
    text = text,
  })
  if not cell then
    return nil, cell_error
  end
  local screen = active_screen(terminal)
  local replaced, replace_error = screen.rows[cursor.row]:replace(cursor.column, cell)
  if not replaced then
    return nil, replace_error
  end
  events[#events + 1] = {
    byte = byte,
    column = cursor.column,
    kind = "output",
    offset = offset,
    row = cursor.row,
  }
  if cursor.column == terminal.config.columns then
    cursor.pending_wrap = true
  else
    cursor.column = cursor.column + 1
    cursor_event(terminal, events, offset)
  end
  return true
end

local function flush_utf8(terminal, events, offset)
  local output = terminal.utf8_decoder:finish()
  for _, text in ipairs(output) do
    local written, write_error = write_printable(terminal, events, offset, nil, text)
    if not written then
      return nil, write_error
    end
  end
  return true
end

function terminal_mt:feed_output(bytes)
  if type(bytes) ~= "string" then
    return nil, Errors.new("config_error", "terminal output must be bytes")
  end
  local parser_events, parser_error = self.parser:feed(bytes)
  if not parser_events then
    return nil, parser_error
  end
  local semantic_events = {}
  for _, event in ipairs(parser_events) do
    if event.kind == "print" then
      local output, decode_error = self.utf8_decoder:push(event.byte)
      if not output then
        return nil, decode_error
      end
      for _, text in ipairs(output) do
        local written, write_error =
          write_printable(self, semantic_events, event.offset, event.byte, text)
        if not written then
          return nil, write_error
        end
      end
    else
      local flushed, flush_error = flush_utf8(self, semantic_events, event.offset)
      if not flushed then
        return nil, flush_error
      end
    end
    if event.kind == "control" then
      local applied, apply_error = apply_control(self, semantic_events, event)
      if not applied then
        return nil, apply_error
      end
    end
  end
  return semantic_events
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
