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
  if
    terminal.active_buffer == "primary"
    and terminal.margins.top == 1
    and terminal.margins.bottom == terminal.config.rows
  then
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

local MAX_CSI_PARAMETER = 65535

local function parse_csi_parameters(raw)
  if raw == "" then
    return {}
  end
  if raw:find("[^0-9;]") then
    return nil
  end
  local values = {}
  for field in (raw .. ";"):gmatch("(.-);") do
    local value = 0
    for index = 1, #field do
      value = math.min(MAX_CSI_PARAMETER, value * 10 + field:byte(index) - string.byte("0"))
    end
    values[#values + 1] = value
  end
  return values
end

local function parameter(values, index, default)
  local value = values[index]
  if value == nil or value == 0 then
    return default
  end
  return value
end

local function current_blank_cell(terminal)
  return Cell.new({
    attributes = terminal.rendition.attributes,
    background = terminal.rendition.background,
    foreground = terminal.rendition.foreground,
  })
end

local function move_cursor(terminal, events, offset, row, column)
  local cursor = terminal.cursor
  local previous_row = cursor.row
  local previous_column = cursor.column
  cursor.row = math.max(1, math.min(terminal.config.rows, row))
  cursor.column = math.max(1, math.min(terminal.config.columns, column))
  cursor.pending_wrap = false
  if cursor.row ~= previous_row or cursor.column ~= previous_column then
    cursor_event(terminal, events, offset)
  end
end

local function erase_rows(
  terminal,
  screen,
  first_row,
  last_row,
  first_column,
  last_column,
  blank_cell
)
  for row = first_row, last_row do
    local start_column = row == first_row and first_column or 1
    local end_column = row == last_row and last_column or terminal.config.columns
    local erased, erase_error =
      screen.rows[row]:erase(start_column, end_column - start_column + 1, blank_cell)
    if not erased then
      return nil, erase_error
    end
  end
  return true
end

local function scroll_up(terminal, events, offset, count, blank_cell)
  local screen = active_screen(terminal)
  local actual = math.min(count, terminal.margins.bottom - terminal.margins.top + 1)
  for _ = 1, actual do
    local displaced, scroll_error =
      screen:scroll_up(terminal.margins.top, terminal.margins.bottom, blank_cell)
    if not displaced then
      return nil, scroll_error
    end
    if
      terminal.active_buffer == "primary"
      and terminal.margins.top == 1
      and terminal.margins.bottom == terminal.config.rows
    then
      local pushed, push_error = terminal.scrollback:push(displaced)
      if not pushed then
        return nil, push_error
      end
    end
  end
  if actual > 0 then
    events[#events + 1] = {
      bottom = terminal.margins.bottom,
      count = actual,
      kind = "scrolled",
      offset = offset,
      top = terminal.margins.top,
    }
  end
  return true
end

local function apply_sgr(terminal, events, offset, values)
  if #values == 0 then
    values = { 0 }
  end
  local rendition = terminal.rendition
  local index = 1
  while index <= #values do
    local code = values[index]
    if code == 0 then
      rendition.attributes = 0
      rendition.background = "default"
      rendition.foreground = "default"
    elseif code == 1 then
      rendition.attributes = rendition.attributes + (rendition.attributes % 2 == 0 and 1 or 0)
    elseif code == 2 then
      rendition.attributes = rendition.attributes
        + (math.floor(rendition.attributes / 2) % 2 == 0 and 2 or 0)
    elseif code == 3 then
      rendition.attributes = rendition.attributes
        + (math.floor(rendition.attributes / 4) % 2 == 0 and 4 or 0)
    elseif code == 4 then
      rendition.attributes = rendition.attributes
        + (math.floor(rendition.attributes / 8) % 2 == 0 and 8 or 0)
    elseif code == 5 or code == 6 then
      rendition.attributes = rendition.attributes
        + (math.floor(rendition.attributes / 16) % 2 == 0 and 16 or 0)
    elseif code == 7 then
      rendition.attributes = rendition.attributes
        + (math.floor(rendition.attributes / 32) % 2 == 0 and 32 or 0)
    elseif code == 8 then
      rendition.attributes = rendition.attributes
        + (math.floor(rendition.attributes / 64) % 2 == 0 and 64 or 0)
    elseif code == 9 then
      rendition.attributes = rendition.attributes
        + (math.floor(rendition.attributes / 128) % 2 == 0 and 128 or 0)
    elseif code == 22 then
      rendition.attributes = rendition.attributes
        - (rendition.attributes % 2)
        - (math.floor(rendition.attributes / 2) % 2) * 2
    elseif code == 23 then
      rendition.attributes = rendition.attributes - (math.floor(rendition.attributes / 4) % 2) * 4
    elseif code == 24 then
      rendition.attributes = rendition.attributes - (math.floor(rendition.attributes / 8) % 2) * 8
    elseif code == 25 then
      rendition.attributes = rendition.attributes - (math.floor(rendition.attributes / 16) % 2) * 16
    elseif code == 27 then
      rendition.attributes = rendition.attributes - (math.floor(rendition.attributes / 32) % 2) * 32
    elseif code == 28 then
      rendition.attributes = rendition.attributes - (math.floor(rendition.attributes / 64) % 2) * 64
    elseif code == 29 then
      rendition.attributes = rendition.attributes
        - (math.floor(rendition.attributes / 128) % 2) * 128
    elseif code >= 30 and code <= 37 then
      rendition.foreground = { index = code - 30, kind = "indexed" }
    elseif code == 39 then
      rendition.foreground = "default"
    elseif code >= 40 and code <= 47 then
      rendition.background = { index = code - 40, kind = "indexed" }
    elseif code == 49 then
      rendition.background = "default"
    elseif code >= 90 and code <= 97 then
      rendition.foreground = { index = code - 90 + 8, kind = "indexed" }
    elseif code >= 100 and code <= 107 then
      rendition.background = { index = code - 100 + 8, kind = "indexed" }
    elseif code == 38 or code == 48 then
      local target = code == 38 and "foreground" or "background"
      local mode = values[index + 1]
      if mode == 5 then
        local colour_index = values[index + 2]
        if colour_index and colour_index <= 255 then
          rendition[target] = { index = colour_index, kind = "indexed" }
        end
        index = index + 2
      elseif mode == 2 then
        local red = values[index + 2]
        local green = values[index + 3]
        local blue = values[index + 4]
        if red and green and blue and red <= 255 and green <= 255 and blue <= 255 then
          rendition[target] = { blue = blue, green = green, kind = "rgb", red = red }
        end
        index = index + 4
      end
    end
    index = index + 1
  end
  events[#events + 1] = { kind = "rendition_changed", offset = offset }
  return true
end

local function apply_csi(terminal, events, event)
  if event.intermediates ~= "" then
    return true
  end
  local values = parse_csi_parameters(event.parameters)
  if not values then
    return true
  end
  local cursor = terminal.cursor
  local screen = active_screen(terminal)
  local final = string.char(event.final)
  if final == "A" then
    move_cursor(terminal, events, event.offset, cursor.row - parameter(values, 1, 1), cursor.column)
  elseif final == "B" then
    move_cursor(terminal, events, event.offset, cursor.row + parameter(values, 1, 1), cursor.column)
  elseif final == "C" then
    move_cursor(terminal, events, event.offset, cursor.row, cursor.column + parameter(values, 1, 1))
  elseif final == "D" then
    move_cursor(terminal, events, event.offset, cursor.row, cursor.column - parameter(values, 1, 1))
  elseif final == "E" then
    move_cursor(terminal, events, event.offset, cursor.row + parameter(values, 1, 1), 1)
  elseif final == "F" then
    move_cursor(terminal, events, event.offset, cursor.row - parameter(values, 1, 1), 1)
  elseif final == "G" then
    move_cursor(terminal, events, event.offset, cursor.row, parameter(values, 1, 1))
  elseif final == "H" or final == "f" then
    move_cursor(terminal, events, event.offset, parameter(values, 1, 1), parameter(values, 2, 1))
  elseif final == "d" then
    move_cursor(terminal, events, event.offset, parameter(values, 1, 1), cursor.column)
  elseif final == "J" then
    local mode = values[1] or 0
    local blank, blank_error = current_blank_cell(terminal)
    if not blank then
      return nil, blank_error
    end
    if mode == 0 then
      return erase_rows(
        terminal,
        screen,
        cursor.row,
        terminal.config.rows,
        cursor.column,
        terminal.config.columns,
        blank
      )
    elseif mode == 1 then
      return erase_rows(terminal, screen, 1, cursor.row, 1, cursor.column, blank)
    elseif mode == 2 then
      return erase_rows(
        terminal,
        screen,
        1,
        terminal.config.rows,
        1,
        terminal.config.columns,
        blank
      )
    end
  elseif final == "K" then
    local mode = values[1] or 0
    local blank, blank_error = current_blank_cell(terminal)
    if not blank then
      return nil, blank_error
    end
    if mode == 0 then
      return screen.rows[cursor.row]:erase(
        cursor.column,
        terminal.config.columns - cursor.column + 1,
        blank
      )
    elseif mode == 1 then
      return screen.rows[cursor.row]:erase(1, cursor.column, blank)
    elseif mode == 2 then
      return screen.rows[cursor.row]:erase(1, terminal.config.columns, blank)
    end
  elseif final == "X" then
    local blank, blank_error = current_blank_cell(terminal)
    if not blank then
      return nil, blank_error
    end
    return screen.rows[cursor.row]:erase(cursor.column, parameter(values, 1, 1), blank)
  elseif final == "@" then
    local blank, blank_error = current_blank_cell(terminal)
    if not blank then
      return nil, blank_error
    end
    return screen.rows[cursor.row]:insert(cursor.column, parameter(values, 1, 1), blank)
  elseif final == "P" then
    local blank, blank_error = current_blank_cell(terminal)
    if not blank then
      return nil, blank_error
    end
    return screen.rows[cursor.row]:delete(cursor.column, parameter(values, 1, 1), blank)
  elseif final == "L" then
    local blank, blank_error = current_blank_cell(terminal)
    if not blank then
      return nil, blank_error
    end
    return screen:insert_lines(
      cursor.row,
      parameter(values, 1, 1),
      terminal.margins.top,
      terminal.margins.bottom,
      blank
    )
  elseif final == "M" then
    local blank, blank_error = current_blank_cell(terminal)
    if not blank then
      return nil, blank_error
    end
    return screen:delete_lines(
      cursor.row,
      parameter(values, 1, 1),
      terminal.margins.top,
      terminal.margins.bottom,
      blank
    )
  elseif final == "S" then
    local blank, blank_error = current_blank_cell(terminal)
    if not blank then
      return nil, blank_error
    end
    return scroll_up(terminal, events, event.offset, parameter(values, 1, 1), blank)
  elseif final == "T" then
    local blank, blank_error = current_blank_cell(terminal)
    if not blank then
      return nil, blank_error
    end
    local moved, move_error = screen:scroll_down(
      terminal.margins.top,
      terminal.margins.bottom,
      parameter(values, 1, 1),
      blank
    )
    if not moved then
      return nil, move_error
    end
    return true
  elseif final == "m" then
    return apply_sgr(terminal, events, event.offset, values)
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
    elseif event.kind == "csi" then
      local applied, apply_error = apply_csi(self, semantic_events, event)
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
