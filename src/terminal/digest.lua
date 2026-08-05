local Cell = require("terminal.cell")
local Errors = require("runtime.errors")
local Rendition = require("terminal.rendition")

local Digest = {}

Digest.contract = {
  terminal = "terminal(terminal) -> canonical_digest | nil, error",
}

local function invariant_error(message, detail)
  return nil, Errors.new("internal_invariant_error", message, detail)
end

local function hex(bytes)
  local encoded = {}
  for index = 1, #bytes do
    encoded[index] = string.format("%02X", string.byte(bytes, index))
  end
  return table.concat(encoded)
end

local function boolean(value, name)
  if type(value) ~= "boolean" then
    return invariant_error(name .. " must be a boolean", { provided = value })
  end
  return value
end

local function positive_integer(value, name)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 then
    return invariant_error(name .. " must be a positive integer", { provided = value })
  end
  return value
end

local function colour(value)
  if value == "default" then
    return "default"
  end
  if value.kind == "indexed" then
    return "indexed:" .. value.index
  end
  return "rgb:" .. value.red .. "," .. value.green .. "," .. value.blue
end

local function cell_digest(cell)
  if type(cell) ~= "table" then
    return invariant_error("screen cell is malformed")
  end
  local normalised, cell_error = Cell.new(cell)
  if not normalised then
    return invariant_error("screen cell is invalid", { cause = cell_error })
  end
  return table.concat({
    "text=" .. hex(normalised.text),
    "width=" .. normalised.width,
    "continuation=" .. tostring(normalised.continuation),
    "attributes=" .. normalised.attributes,
    "foreground=" .. colour(normalised.foreground),
    "background=" .. colour(normalised.background),
    "hyperlink=nil",
  }, ",")
end

local function row_digest(row, columns)
  if type(row) ~= "table" or type(row.cells) ~= "table" or row.columns ~= columns then
    return invariant_error("screen row is malformed")
  end
  local wrapped, wrapped_error = boolean(row.wrapped, "row wrapped state")
  if wrapped == nil then
    return nil, wrapped_error
  end
  local cells = {}
  for column = 1, columns do
    local digest, cell_error = cell_digest(row.cells[column])
    if not digest then
      return nil, cell_error
    end
    cells[column] = digest
  end
  return "wrapped=" .. tostring(wrapped) .. ";cells=[" .. table.concat(cells, "|") .. "]"
end

local function screen_digest(name, screen, expected_columns, expected_rows)
  if type(screen) ~= "table" or type(screen.rows) ~= "table" then
    return invariant_error(name .. " screen is malformed")
  end
  if screen.columns ~= expected_columns or screen.height ~= expected_rows then
    return invariant_error(name .. " screen dimensions disagree with terminal config")
  end
  local rows = {}
  for index = 1, expected_rows do
    local digest, row_error = row_digest(screen.rows[index], expected_columns)
    if not digest then
      return nil, row_error
    end
    rows[index] = digest
  end
  return name .. "=[" .. table.concat(rows, ";") .. "]"
end

local function cursor_digest(name, cursor, columns, rows)
  if type(cursor) ~= "table" then
    return invariant_error(name .. " cursor is malformed")
  end
  local column, column_error = positive_integer(cursor.column, name .. " cursor column")
  if not column then
    return nil, column_error
  end
  if column > columns then
    return invariant_error(name .. " cursor column is outside the terminal")
  end
  local row, row_error = positive_integer(cursor.row, name .. " cursor row")
  if not row then
    return nil, row_error
  end
  if row > rows then
    return invariant_error(name .. " cursor row is outside the terminal")
  end
  local pending_wrap, pending_wrap_error =
    boolean(cursor.pending_wrap, name .. " cursor pending_wrap")
  if pending_wrap == nil then
    return nil, pending_wrap_error
  end
  return name
    .. "=row:"
    .. row
    .. ",column:"
    .. column
    .. ",pending_wrap:"
    .. tostring(pending_wrap)
end

local function rendition_digest(rendition)
  if type(rendition) ~= "table" then
    return invariant_error("terminal rendition is malformed")
  end
  local normalised, rendition_error = Rendition.copy(rendition)
  if not normalised then
    return invariant_error("terminal rendition is invalid", { cause = rendition_error })
  end
  return table.concat({
    "attributes=" .. normalised.attributes,
    "foreground=" .. colour(normalised.foreground),
    "background=" .. colour(normalised.background),
  }, ",")
end

local function modes_digest(modes)
  if type(modes) ~= "table" then
    return invariant_error("terminal modes are malformed")
  end
  local auto_wrap, auto_wrap_error = boolean(modes.auto_wrap, "terminal auto-wrap mode")
  if auto_wrap == nil then
    return nil, auto_wrap_error
  end
  local cursor_visible, cursor_visible_error =
    boolean(modes.cursor_visible, "terminal cursor visibility mode")
  if cursor_visible == nil then
    return nil, cursor_visible_error
  end
  return "auto_wrap=" .. tostring(auto_wrap) .. ",cursor_visible=" .. tostring(cursor_visible)
end

local function tab_stops_digest(tab_stops, columns)
  if type(tab_stops) ~= "table" then
    return invariant_error("tab stops are malformed")
  end
  local columns_with_stops = {}
  for column = 1, columns do
    if tab_stops[column] ~= nil and type(tab_stops[column]) ~= "boolean" then
      return invariant_error("tab stop value must be a boolean", { column = column })
    end
    if tab_stops[column] then
      columns_with_stops[#columns_with_stops + 1] = column
    end
  end
  return table.concat(columns_with_stops, ",")
end

local parser_states = {
  csi_entry = true,
  csi_ignore = true,
  csi_intermediate = true,
  csi_parameter = true,
  escape = true,
  escape_ignore = true,
  ground = true,
  osc_escape = true,
  osc_ignore = true,
  osc_ignore_escape = true,
  osc_string = true,
}

local function parser_digest(parser)
  if type(parser) ~= "table" or type(parser.snapshot) ~= "function" then
    return invariant_error("terminal parser is malformed")
  end
  local state = parser:snapshot()
  if type(state) ~= "table" or not parser_states[state.state] then
    return invariant_error("terminal parser state is invalid")
  end
  if type(state.byte_offset) ~= "number" or state.byte_offset % 1 ~= 0 or state.byte_offset < 0 then
    return invariant_error("terminal parser byte offset is invalid")
  end
  for _, name in ipairs({
    "csi_intermediates",
    "csi_parameters",
    "escape_intermediates",
    "osc_payload",
  }) do
    if type(state[name]) ~= "string" then
      return invariant_error("terminal parser buffer is invalid", { buffer = name })
    end
  end
  for _, name in ipairs({ "max_csi_bytes", "max_escape_intermediate_bytes", "max_osc_bytes" }) do
    if type(state[name]) ~= "number" or state[name] % 1 ~= 0 or state[name] < 1 then
      return invariant_error("terminal parser bound is invalid", { bound = name })
    end
  end
  return table.concat({
    "state=" .. state.state,
    "byte_offset=" .. state.byte_offset,
    "csi_intermediates=" .. hex(state.csi_intermediates),
    "csi_parameters=" .. hex(state.csi_parameters),
    "escape_intermediates=" .. hex(state.escape_intermediates),
    "osc_payload=" .. hex(state.osc_payload),
    "max_csi_bytes=" .. state.max_csi_bytes,
    "max_escape_intermediate_bytes=" .. state.max_escape_intermediate_bytes,
    "max_osc_bytes=" .. state.max_osc_bytes,
  }, ",")
end

local function utf8_digest(decoder)
  if type(decoder) ~= "table" or type(decoder.snapshot) ~= "function" then
    return invariant_error("terminal UTF-8 decoder is malformed")
  end
  local state = decoder:snapshot()
  if type(state) ~= "table" then
    return invariant_error("terminal UTF-8 decoder state is malformed")
  end
  for _, name in ipairs({ "codepoint", "minimum", "remaining" }) do
    if type(state[name]) ~= "number" or state[name] % 1 ~= 0 or state[name] < 0 then
      return invariant_error("terminal UTF-8 decoder state is invalid", { field = name })
    end
  end
  return "codepoint="
    .. state.codepoint
    .. ",minimum="
    .. state.minimum
    .. ",remaining="
    .. state.remaining
end

local function scrollback_digest(scrollback)
  if
    type(scrollback) ~= "table"
    or type(scrollback.count) ~= "number"
    or type(scrollback.limit) ~= "number"
    or type(scrollback.at) ~= "function"
  then
    return invariant_error("scrollback is malformed")
  end
  if
    scrollback.count < 0
    or scrollback.count % 1 ~= 0
    or scrollback.limit < 0
    or scrollback.limit % 1 ~= 0
    or scrollback.count > scrollback.limit
  then
    return invariant_error("scrollback count is invalid")
  end
  local rows = {}
  for index = 1, scrollback.count do
    local row, row_error = scrollback:at(index)
    if not row then
      return nil, row_error
    end
    local digest, digest_error = row_digest(row, row.columns)
    if not digest then
      return nil, digest_error
    end
    rows[index] = digest
  end
  return "limit=" .. scrollback.limit .. ";rows=[" .. table.concat(rows, ";") .. "]"
end

function Digest.terminal(terminal)
  if type(terminal) ~= "table" or type(terminal.config) ~= "table" then
    return invariant_error("terminal is malformed")
  end
  local columns, columns_error = positive_integer(terminal.config.columns, "terminal columns")
  if not columns then
    return nil, columns_error
  end
  local rows, rows_error = positive_integer(terminal.config.rows, "terminal rows")
  if not rows then
    return nil, rows_error
  end
  if type(terminal.config.compatibility_profile) ~= "string" then
    return invariant_error("terminal compatibility profile is malformed")
  end
  if terminal.active_buffer ~= "primary" and terminal.active_buffer ~= "alternate" then
    return invariant_error("terminal active buffer is invalid")
  end
  if
    type(terminal.config.scrollback_limit) ~= "number"
    or terminal.config.scrollback_limit % 1 ~= 0
    or terminal.config.scrollback_limit < 0
  then
    return invariant_error("terminal scrollback limit is malformed")
  end
  if type(terminal.margins) ~= "table" then
    return invariant_error("terminal margins are invalid")
  end
  local margin_top, margin_top_error = positive_integer(terminal.margins.top, "terminal margin top")
  if not margin_top then
    return nil, margin_top_error
  end
  local margin_bottom, margin_bottom_error =
    positive_integer(terminal.margins.bottom, "terminal margin bottom")
  if not margin_bottom then
    return nil, margin_bottom_error
  end
  if margin_top > margin_bottom or margin_bottom > rows then
    return invariant_error("terminal margins are invalid")
  end
  local cursor, cursor_error = cursor_digest("cursor", terminal.cursor, columns, rows)
  if not cursor then
    return nil, cursor_error
  end
  local saved_cursor, saved_cursor_error =
    cursor_digest("saved_cursor", terminal.saved_cursor, columns, rows)
  if not saved_cursor then
    return nil, saved_cursor_error
  end
  local rendition, rendition_error = rendition_digest(terminal.rendition)
  if not rendition then
    return nil, rendition_error
  end
  local saved_rendition, saved_rendition_error = rendition_digest(terminal.saved_rendition)
  if not saved_rendition then
    return nil, saved_rendition_error
  end
  local modes, modes_error = modes_digest(terminal.modes)
  if not modes then
    return nil, modes_error
  end
  local tab_stops, tab_stops_error = tab_stops_digest(terminal.tab_stops, columns)
  if not tab_stops then
    return nil, tab_stops_error
  end
  local parser, parser_error = parser_digest(terminal.parser)
  if not parser then
    return nil, parser_error
  end
  local utf8_decoder, utf8_error = utf8_digest(terminal.utf8_decoder)
  if not utf8_decoder then
    return nil, utf8_error
  end
  local primary_screen, primary_screen_error =
    screen_digest("primary", terminal.primary_screen, columns, rows)
  if not primary_screen then
    return nil, primary_screen_error
  end
  local alternate_screen, alternate_screen_error =
    screen_digest("alternate", terminal.alternate_screen, columns, rows)
  if not alternate_screen then
    return nil, alternate_screen_error
  end
  local scrollback, scrollback_error = scrollback_digest(terminal.scrollback)
  if not scrollback then
    return nil, scrollback_error
  end
  if terminal.scrollback.limit ~= terminal.config.scrollback_limit then
    return invariant_error("terminal scrollback limit disagrees with terminal config")
  end
  return table.concat({
    "profile=" .. terminal.config.compatibility_profile,
    "size=" .. columns .. "x" .. rows,
    "active_buffer=" .. terminal.active_buffer,
    cursor,
    saved_cursor,
    "margins=top:" .. margin_top .. ",bottom:" .. margin_bottom,
    "tab_stops=" .. tab_stops,
    "rendition=" .. rendition,
    "saved_rendition=" .. saved_rendition,
    "modes=" .. modes,
    "parser=" .. parser,
    "utf8=" .. utf8_decoder,
    primary_screen,
    alternate_screen,
    "scrollback=" .. scrollback,
  }, "\n")
end

return Digest
