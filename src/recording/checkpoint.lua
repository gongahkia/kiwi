local Binary = require("recording.binary")
local Cell = require("terminal.cell")
local Config = require("terminal.config")
local Cursor = require("terminal.cursor")
local Errors = require("runtime.errors")
local Rendition = require("terminal.rendition")
local Row = require("terminal.row")
local Terminal = require("terminal.terminal")

local Checkpoint = {}

Checkpoint.schema_version = 2
Checkpoint.supported_schema_versions = { [1] = true, [2] = true }
Checkpoint.defaults = {
  max_cell_text_bytes = 4096,
  max_checkpoint_bytes = 16 * 1024 * 1024,
  max_cells_per_screen = 262144,
  max_parser_buffer_bytes = 65536,
  max_scrollback_rows = 100000,
  max_total_cells = 524288,
}
Checkpoint.contract = {
  decode = "decode(bytes, limits?) -> terminal | nil, error",
  encode = "encode(terminal, limits?) -> payload | nil, error",
}

local MAX_EXACT_U53 = 9007199254740991
local parser_states = {
  { name = "ground", value = 0 },
  { name = "escape", value = 1 },
  { name = "escape_ignore", value = 2 },
  { name = "csi_entry", value = 3 },
  { name = "csi_parameter", value = 4 },
  { name = "csi_intermediate", value = 5 },
  { name = "csi_ignore", value = 6 },
  { name = "osc_string", value = 7 },
  { name = "osc_escape", value = 8 },
  { name = "osc_ignore", value = 9 },
  { name = "osc_ignore_escape", value = 10 },
}
local parser_state_by_name = {}
local parser_state_by_value = {}
for _, state in ipairs(parser_states) do
  parser_state_by_name[state.name] = state.value
  parser_state_by_value[state.value] = state.name
end
local limit_names = {
  "max_cell_text_bytes",
  "max_checkpoint_bytes",
  "max_cells_per_screen",
  "max_parser_buffer_bytes",
  "max_scrollback_rows",
  "max_total_cells",
}
local parser_bound_names = { "max_csi_bytes", "max_escape_intermediate_bytes", "max_osc_bytes" }
local parser_buffer_names =
  { "csi_intermediates", "csi_parameters", "escape_intermediates", "osc_payload" }

local function corrupt(message, detail)
  return nil, Errors.new("recording_corrupt", message, detail)
end

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function nonnegative_integer(value, name)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > MAX_EXACT_U53 then
    return config_error(name .. " must be a non-negative exact integer", { provided = value })
  end
  return value
end

local function limits_for(requested)
  if requested == nil then
    requested = {}
  end
  if type(requested) ~= "table" then
    return config_error("checkpoint limits must be a table", { provided = requested })
  end
  local values = {}
  for _, name in ipairs(limit_names) do
    local default = Checkpoint.defaults[name]
    local value = requested[name]
    if value == nil then
      value = default
    end
    local valid, value_error = nonnegative_integer(value, "checkpoint " .. name)
    if not valid then
      return nil, value_error
    end
    values[name] = valid
  end
  return values
end

local function boolean_byte(value, name)
  if type(value) ~= "boolean" then
    return config_error(name .. " must be a boolean", { provided = value })
  end
  return value and 1 or 0
end

local function decode_boolean(value, name)
  if value == 0 then
    return false
  end
  if value == 1 then
    return true
  end
  return corrupt(name .. " must be 0 or 1", { provided = value })
end

local function u53(value)
  local valid, value_error = nonnegative_integer(value, "parser byte offset")
  if not valid then
    return nil, value_error
  end
  local output = {}
  for index = 7, 1, -1 do
    output[index] = string.char(value % 0x100)
    value = math.floor(value / 0x100)
  end
  return table.concat(output)
end

local function read_u53(bytes, offset)
  if offset + 6 > #bytes then
    return corrupt("truncated parser byte offset", { offset = offset })
  end
  local value = 0
  for index = offset, offset + 6 do
    value = value * 0x100 + bytes:byte(index)
  end
  return value, offset + 7
end

local function valid_colour(colour)
  if colour == "default" then
    return true
  end
  if type(colour) ~= "table" then
    return nil
  end
  if colour.kind == "indexed" then
    return type(colour.index) == "number"
      and colour.index % 1 == 0
      and colour.index >= 0
      and colour.index <= 255
  end
  return colour.kind == "rgb"
    and type(colour.red) == "number"
    and colour.red % 1 == 0
    and colour.red >= 0
    and colour.red <= 255
    and type(colour.green) == "number"
    and colour.green % 1 == 0
    and colour.green >= 0
    and colour.green <= 255
    and type(colour.blue) == "number"
    and colour.blue % 1 == 0
    and colour.blue >= 0
    and colour.blue <= 255
end

local function encode_colour(colour)
  if colour == "default" then
    return "\0"
  end
  if not valid_colour(colour) then
    return config_error("checkpoint colour is invalid")
  end
  if colour.kind == "indexed" then
    return "\1" .. assert(Binary.u8(colour.index))
  end
  return "\2"
    .. assert(Binary.u8(colour.red))
    .. assert(Binary.u8(colour.green))
    .. assert(Binary.u8(colour.blue))
end

local function encode_rendition(rendition)
  if type(rendition) ~= "table" then
    return config_error("checkpoint rendition is invalid")
  end
  local normalised, rendition_error = Rendition.new({
    attributes = rendition.attributes,
    background = rendition.background,
    foreground = rendition.foreground,
  })
  if not normalised then
    return nil, rendition_error
  end
  local foreground, foreground_error = encode_colour(normalised.foreground)
  if not foreground then
    return nil, foreground_error
  end
  local background, background_error = encode_colour(normalised.background)
  if not background then
    return nil, background_error
  end
  return assert(Binary.u32(normalised.attributes)) .. foreground .. background
end

local function decode_colour(reader)
  local kind, kind_error = reader:u8("colour kind")
  if not kind then
    return nil, kind_error
  end
  if kind == 0 then
    return "default"
  end
  if kind == 1 then
    local index, index_error = reader:u8("indexed colour")
    if not index then
      return nil, index_error
    end
    return { index = index, kind = "indexed" }
  end
  if kind == 2 then
    local red, red_error = reader:u8("RGB red")
    if not red then
      return nil, red_error
    end
    local green, green_error = reader:u8("RGB green")
    if not green then
      return nil, green_error
    end
    local blue, blue_error = reader:u8("RGB blue")
    if not blue then
      return nil, blue_error
    end
    return { blue = blue, green = green, kind = "rgb", red = red }
  end
  return corrupt("checkpoint colour discriminant is invalid", { provided = kind })
end

local function decode_rendition(reader)
  local attributes, attributes_error = reader:u32("rendition attributes")
  if not attributes then
    return nil, attributes_error
  end
  local foreground, foreground_error = decode_colour(reader)
  if not foreground then
    return nil, foreground_error
  end
  local background, background_error = decode_colour(reader)
  if not background then
    return nil, background_error
  end
  local rendition, rendition_error = Rendition.new({
    attributes = attributes,
    background = background,
    foreground = foreground,
  })
  if not rendition then
    return corrupt("checkpoint rendition is invalid", { cause = rendition_error })
  end
  return rendition
end

local function encode_cell(cell, limits)
  if type(cell) ~= "table" then
    return config_error("checkpoint cell is missing")
  end
  local normalised, cell_error = Cell.new(cell)
  if not normalised then
    return nil, cell_error
  end
  if #normalised.text > limits.max_cell_text_bytes or #normalised.text > 0xFFFF then
    return config_error(
      "checkpoint cell text exceeds configured limit",
      { length = #normalised.text }
    )
  end
  local rendition, rendition_error = encode_rendition(normalised)
  if not rendition then
    return nil, rendition_error
  end
  return assert(Binary.u16(#normalised.text))
    .. normalised.text
    .. assert(Binary.u8(normalised.width))
    .. rendition
end

local function decode_cell(reader, limits)
  local text_length, length_error = reader:u16("cell text length")
  if not text_length then
    return nil, length_error
  end
  if text_length > limits.max_cell_text_bytes then
    return corrupt("checkpoint cell text exceeds configured limit", { length = text_length })
  end
  local text, text_error = reader:bytes(text_length, "cell text")
  if not text then
    return nil, text_error
  end
  local width, width_error = reader:u8("cell width")
  if not width then
    return nil, width_error
  end
  if width > 2 then
    return corrupt("checkpoint cell width is invalid", { provided = width })
  end
  local rendition, rendition_error = decode_rendition(reader)
  if not rendition then
    return nil, rendition_error
  end
  local cell, cell_error = Cell.new({
    attributes = rendition.attributes,
    background = rendition.background,
    continuation = width == 0,
    foreground = rendition.foreground,
    text = text,
    width = width,
  })
  if not cell then
    return corrupt("checkpoint cell is invalid", { cause = cell_error })
  end
  return cell
end

local function encode_row(row, expected_columns, limits)
  if type(row) ~= "table" or type(row.cells) ~= "table" then
    return config_error("checkpoint row dimensions are invalid")
  end
  local columns = row.columns
  if expected_columns ~= nil and columns ~= expected_columns then
    return config_error("checkpoint row dimensions are invalid")
  end
  local config = Config.new({ columns = columns })
  if not config then
    return config_error("checkpoint row dimensions are invalid")
  end
  columns = config.columns
  local wrapped, wrapped_error = boolean_byte(row.wrapped, "checkpoint row wrapping state")
  if not wrapped then
    return nil, wrapped_error
  end
  local output = { assert(Binary.u8(wrapped)), assert(Binary.u16(columns)) }
  for column = 1, columns do
    local cell, cell_error = encode_cell(row.cells[column], limits)
    if not cell then
      return nil, cell_error
    end
    output[#output + 1] = cell
  end
  return table.concat(output)
end

local function encode_screen(screen, columns, rows, limits)
  if
    type(screen) ~= "table"
    or screen.columns ~= columns
    or screen.height ~= rows
    or type(screen.rows) ~= "table"
  then
    return config_error("checkpoint screen dimensions are invalid")
  end
  local output = { assert(Binary.u16(rows)) }
  for row = 1, rows do
    local encoded, row_error = encode_row(screen.rows[row], columns, limits)
    if not encoded then
      return nil, row_error
    end
    output[#output + 1] = encoded
  end
  return table.concat(output)
end

local function decode_row(reader, expected_columns, limits)
  local wrapped_value, wrapped_error = reader:u8("row wrapping state")
  if not wrapped_value then
    return nil, wrapped_error
  end
  local wrapped, boolean_error = decode_boolean(wrapped_value, "row wrapping state")
  if wrapped == nil then
    return nil, boolean_error
  end
  local cell_count, count_error = reader:u16("row cell count")
  if not cell_count then
    return nil, count_error
  end
  if expected_columns ~= nil and cell_count ~= expected_columns then
    return corrupt("checkpoint row cell count disagrees with dimensions", {
      actual = cell_count,
      expected = expected_columns,
    })
  end
  local columns = cell_count
  if expected_columns == nil then
    local config, config_error_value = Config.new({ columns = columns })
    if not config then
      return corrupt("checkpoint scrollback row dimensions are invalid", {
        cause = config_error_value,
      })
    end
    columns = config.columns
  end
  local cells = {}
  for column = 1, columns do
    local cell, cell_error = decode_cell(reader, limits)
    if not cell then
      return nil, cell_error
    end
    cells[column] = cell
  end
  return { cells = cells, columns = columns, wrapped = wrapped }
end

local function decode_screen(reader, columns, rows, limits)
  local row_count, count_error = reader:u16("screen row count")
  if not row_count then
    return nil, count_error
  end
  if row_count ~= rows then
    return corrupt("checkpoint screen row count disagrees with dimensions", {
      actual = row_count,
      expected = rows,
    })
  end
  local decoded_rows = {}
  for row = 1, rows do
    local decoded, row_error = decode_row(reader, columns, limits)
    if not decoded then
      return nil, row_error
    end
    decoded_rows[row] = decoded
  end
  return decoded_rows
end

local function parser_buffers_valid(state)
  local csi_bytes = #state.csi_intermediates + #state.csi_parameters
  if
    csi_bytes > state.max_csi_bytes
    or #state.escape_intermediates > state.max_escape_intermediate_bytes
    or #state.osc_payload > state.max_osc_bytes
  then
    return nil
  end
  if
    state.state == "ground"
    or state.state == "escape_ignore"
    or state.state == "csi_entry"
    or state.state == "csi_ignore"
    or state.state == "osc_ignore"
    or state.state == "osc_ignore_escape"
  then
    return csi_bytes == 0 and #state.escape_intermediates == 0 and #state.osc_payload == 0
  end
  if state.state == "escape" then
    return csi_bytes == 0 and #state.osc_payload == 0
  end
  if state.state == "csi_parameter" then
    return #state.csi_parameters > 0
      and #state.escape_intermediates == 0
      and #state.osc_payload == 0
  end
  if state.state == "csi_intermediate" then
    return #state.csi_intermediates > 0
      and #state.escape_intermediates == 0
      and #state.osc_payload == 0
  end
  if state.state == "osc_string" or state.state == "osc_escape" then
    return csi_bytes == 0 and #state.escape_intermediates == 0
  end
  return nil
end

local function encode_parser(parser, limits)
  if type(parser) ~= "table" or type(parser.snapshot) ~= "function" then
    return config_error("checkpoint parser is invalid")
  end
  local state = parser:snapshot()
  if type(state) ~= "table" or parser_state_by_name[state.state] == nil then
    return config_error("checkpoint parser state is invalid")
  end
  local byte_offset, offset_error = nonnegative_integer(state.byte_offset, "parser byte offset")
  if not byte_offset then
    return nil, offset_error
  end
  for _, name in ipairs(parser_bound_names) do
    if
      type(state[name]) ~= "number"
      or state[name] % 1 ~= 0
      or state[name] < 1
      or state[name] > limits.max_parser_buffer_bytes
    then
      return config_error(
        "checkpoint parser bound exceeds configured limit",
        { bound = name, provided = state[name] }
      )
    end
  end
  for _, name in ipairs(parser_buffer_names) do
    if type(state[name]) ~= "string" or #state[name] > limits.max_parser_buffer_bytes then
      return config_error("checkpoint parser buffer exceeds configured limit", { buffer = name })
    end
  end
  if not parser_buffers_valid(state) then
    return config_error("checkpoint parser buffers are inconsistent with parser state")
  end
  return assert(Binary.u8(parser_state_by_name[state.state]))
    .. assert(u53(byte_offset))
    .. assert(Binary.u32(state.max_csi_bytes))
    .. assert(Binary.u32(state.max_escape_intermediate_bytes))
    .. assert(Binary.u32(state.max_osc_bytes))
    .. assert(Binary.u32(#state.csi_intermediates))
    .. state.csi_intermediates
    .. assert(Binary.u32(#state.csi_parameters))
    .. state.csi_parameters
    .. assert(Binary.u32(#state.escape_intermediates))
    .. state.escape_intermediates
    .. assert(Binary.u32(#state.osc_payload))
    .. state.osc_payload
end

local function decode_parser(reader, limits)
  local discriminant, state_error = reader:u8("parser state")
  if not discriminant then
    return nil, state_error
  end
  local state_name = parser_state_by_value[discriminant]
  if not state_name then
    return corrupt("checkpoint parser state discriminant is invalid", { provided = discriminant })
  end
  local byte_offset, offset_error = read_u53(reader.bytes_value, reader.offset)
  if not byte_offset then
    return nil, offset_error
  end
  reader.offset = offset_error
  local max_csi_bytes, csi_limit_error = reader:u32("maximum CSI bytes")
  if not max_csi_bytes then
    return nil, csi_limit_error
  end
  local max_escape_intermediate_bytes, escape_limit_error =
    reader:u32("maximum escape-intermediate bytes")
  if not max_escape_intermediate_bytes then
    return nil, escape_limit_error
  end
  local max_osc_bytes, osc_limit_error = reader:u32("maximum OSC bytes")
  if not max_osc_bytes then
    return nil, osc_limit_error
  end
  local parser_bounds = {
    max_csi_bytes = max_csi_bytes,
    max_escape_intermediate_bytes = max_escape_intermediate_bytes,
    max_osc_bytes = max_osc_bytes,
  }
  for _, name in ipairs(parser_bound_names) do
    local value = parser_bounds[name]
    if value < 1 or value > 65536 or value > limits.max_parser_buffer_bytes then
      return corrupt(
        "checkpoint parser bound exceeds configured limit",
        { bound = name, provided = value }
      )
    end
  end
  local buffers = {}
  for _, name in ipairs(parser_buffer_names) do
    local length, length_error = reader:u32("parser buffer length")
    if not length then
      return nil, length_error
    end
    if length > limits.max_parser_buffer_bytes then
      return corrupt(
        "checkpoint parser buffer exceeds configured limit",
        { buffer = name, length = length }
      )
    end
    local value, value_error = reader:bytes(length, "parser buffer")
    if not value then
      return nil, value_error
    end
    buffers[name] = value
  end
  local parser = {
    byte_offset = byte_offset,
    csi_intermediates = buffers.csi_intermediates,
    csi_parameters = buffers.csi_parameters,
    escape_intermediates = buffers.escape_intermediates,
    max_csi_bytes = max_csi_bytes,
    max_escape_intermediate_bytes = max_escape_intermediate_bytes,
    max_osc_bytes = max_osc_bytes,
    osc_payload = buffers.osc_payload,
    state = state_name,
  }
  if not parser_buffers_valid(parser) then
    return corrupt("checkpoint parser buffers are inconsistent with parser state")
  end
  return parser
end

local function utf8_valid(state)
  if state.remaining == 0 then
    return state.codepoint == 0 and state.minimum == 0
  end
  local continuation_count
  local initial_maximum
  if state.minimum == 0x80 then
    continuation_count = 1
    initial_maximum = 0x1F
  elseif state.minimum == 0x800 then
    continuation_count = 2
    initial_maximum = 0x0F
  elseif state.minimum == 0x10000 then
    continuation_count = 3
    initial_maximum = 0x04
  else
    return false
  end
  if state.remaining < 1 or state.remaining > continuation_count then
    return false
  end
  local consumed = continuation_count - state.remaining
  local factor = 1
  for _ = 1, consumed do
    factor = factor * 0x40
  end
  return state.codepoint >= 0 and state.codepoint <= initial_maximum * factor + factor - 1
end

local function encode_utf8(decoder)
  if type(decoder) ~= "table" or type(decoder.snapshot) ~= "function" then
    return config_error("checkpoint UTF-8 decoder is invalid")
  end
  local state = decoder:snapshot()
  if type(state) ~= "table" then
    return config_error("checkpoint UTF-8 decoder state is invalid")
  end
  for _, name in ipairs({ "codepoint", "minimum", "remaining" }) do
    if type(state[name]) ~= "number" or state[name] % 1 ~= 0 or state[name] < 0 then
      return config_error("checkpoint UTF-8 decoder state is invalid", { field = name })
    end
  end
  if
    state.codepoint > 0xFFFFFFFF
    or state.minimum > 0xFFFFFFFF
    or state.remaining > 0xFF
    or not utf8_valid(state)
  then
    return config_error("checkpoint UTF-8 decoder state is inconsistent")
  end
  return assert(Binary.u32(state.codepoint))
    .. assert(Binary.u32(state.minimum))
    .. assert(Binary.u8(state.remaining))
end

local function decode_utf8(reader)
  local codepoint, codepoint_error = reader:u32("UTF-8 codepoint")
  if not codepoint then
    return nil, codepoint_error
  end
  local minimum, minimum_error = reader:u32("UTF-8 minimum")
  if not minimum then
    return nil, minimum_error
  end
  local remaining, remaining_error = reader:u8("UTF-8 remaining")
  if not remaining then
    return nil, remaining_error
  end
  local state = { codepoint = codepoint, minimum = minimum, remaining = remaining }
  if not utf8_valid(state) then
    return corrupt("checkpoint UTF-8 decoder state is inconsistent")
  end
  return state
end

local function encode_tab_stops(tab_stops, columns)
  if type(tab_stops) ~= "table" then
    return config_error("checkpoint tab stops are invalid")
  end
  local byte_count = math.floor((columns + 7) / 8)
  local bytes = {}
  for index = 1, byte_count do
    local value = 0
    for bit_index = 0, 7 do
      local column = (index - 1) * 8 + bit_index + 1
      if column <= columns then
        if tab_stops[column] ~= nil and type(tab_stops[column]) ~= "boolean" then
          return config_error("checkpoint tab stop is invalid", { column = column })
        end
        if tab_stops[column] then
          value = value + 2 ^ bit_index
        end
      end
    end
    bytes[index] = string.char(value)
  end
  return assert(Binary.u16(byte_count)) .. table.concat(bytes)
end

local function decode_tab_stops(reader, columns)
  local byte_count, length_error = reader:u16("tab-stop byte count")
  if not byte_count then
    return nil, length_error
  end
  local expected = math.floor((columns + 7) / 8)
  if byte_count ~= expected then
    return corrupt("checkpoint tab-stop byte count disagrees with dimensions", {
      actual = byte_count,
      expected = expected,
    })
  end
  local bits, bits_error = reader:bytes(byte_count, "tab stops")
  if not bits then
    return nil, bits_error
  end
  local remainder = columns % 8
  if remainder ~= 0 and math.floor(bits:byte(byte_count) / 2 ^ remainder) ~= 0 then
    return corrupt("checkpoint tab-stop padding bits are nonzero")
  end
  local stops = {}
  for column = 1, columns do
    local offset = math.floor((column - 1) / 8) + 1
    local bit_index = (column - 1) % 8
    if math.floor(bits:byte(offset) / 2 ^ bit_index) % 2 == 1 then
      stops[column] = true
    end
  end
  return stops
end

local function encode_cursor(cursor, columns, rows)
  local normalised, cursor_error = Cursor.copy(cursor)
  if not normalised then
    return nil, cursor_error
  end
  if normalised.column > columns or normalised.row > rows then
    return config_error("checkpoint cursor is outside terminal dimensions")
  end
  local pending_wrap, wrap_error =
    boolean_byte(normalised.pending_wrap, "checkpoint cursor pending-wrap state")
  if not pending_wrap then
    return nil, wrap_error
  end
  return assert(Binary.u16(normalised.row))
    .. assert(Binary.u16(normalised.column))
    .. assert(Binary.u8(pending_wrap))
end

local function decode_cursor(reader, columns, rows, name)
  local row, row_error = reader:u16(name .. " cursor row")
  if not row then
    return nil, row_error
  end
  local column, column_error = reader:u16(name .. " cursor column")
  if not column then
    return nil, column_error
  end
  local pending_wrap_value, pending_wrap_error = reader:u8(name .. " cursor pending-wrap state")
  if not pending_wrap_value then
    return nil, pending_wrap_error
  end
  local pending_wrap, boolean_error =
    decode_boolean(pending_wrap_value, name .. " cursor pending-wrap state")
  if pending_wrap == nil then
    return nil, boolean_error
  end
  if row < 1 or row > rows or column < 1 or column > columns then
    return corrupt("checkpoint " .. name .. " cursor is outside terminal dimensions")
  end
  return { column = column, pending_wrap = pending_wrap, row = row }
end

local function reader_for(bytes)
  local reader = { bytes_value = bytes, offset = 1 }
  function reader:u8(name)
    local value, next_offset = Binary.read_u8(self.bytes_value, self.offset)
    if not value then
      return corrupt("truncated checkpoint " .. name, { offset = self.offset })
    end
    self.offset = next_offset
    return value
  end
  function reader:u16(name)
    local value, next_offset = Binary.read_u16(self.bytes_value, self.offset)
    if not value then
      return corrupt("truncated checkpoint " .. name, { offset = self.offset })
    end
    self.offset = next_offset
    return value
  end
  function reader:u32(name)
    local value, next_offset = Binary.read_u32(self.bytes_value, self.offset)
    if not value then
      return corrupt("truncated checkpoint " .. name, { offset = self.offset })
    end
    self.offset = next_offset
    return value
  end
  function reader:bytes(length, name)
    if self.offset + length - 1 > #self.bytes_value then
      return corrupt("truncated checkpoint " .. name, { length = length, offset = self.offset })
    end
    local output = self.bytes_value:sub(self.offset, self.offset + length - 1)
    self.offset = self.offset + length
    return output
  end
  return reader
end

local function restore_rows(target_rows, rows, columns)
  for index = 1, #rows do
    local target = target_rows[index]
    target.cells = rows[index].cells
    target.wrapped = rows[index].wrapped
    target.revision = 0
    target:mark_all_dirty()
  end
  return true
end

local function restore_scrollback(terminal, rows)
  local entries = {}
  for index = 1, #rows do
    local row, row_error = Row.new(rows[index].columns)
    if not row then
      return nil, row_error
    end
    row.cells = rows[index].cells
    row.wrapped = rows[index].wrapped
    row.revision = 0
    row:mark_all_dirty()
    entries[index] = row
  end
  terminal.scrollback.count = #entries
  terminal.scrollback.entries = entries
  terminal.scrollback.first = 1
  return true
end

function Checkpoint.encode(terminal, requested_limits)
  local limits, limits_error = limits_for(requested_limits)
  if not limits then
    return nil, limits_error
  end
  if type(terminal) ~= "table" or type(terminal.config) ~= "table" then
    return config_error("checkpoint terminal is invalid")
  end
  local config, terminal_config_error = Config.new({
    columns = terminal.config.columns,
    compatibility_profile = terminal.config.compatibility_profile,
    rows = terminal.config.rows,
    scrollback_limit = terminal.config.scrollback_limit,
  })
  if not config then
    return nil, terminal_config_error
  end
  local cells_per_screen = config.columns * config.rows
  if
    cells_per_screen > limits.max_cells_per_screen
    or cells_per_screen * 2 > limits.max_total_cells
  then
    return config_error("checkpoint dimensions exceed configured cell limit")
  end
  if terminal.active_buffer ~= "primary" and terminal.active_buffer ~= "alternate" then
    return config_error("checkpoint active screen is invalid")
  end
  if
    type(terminal.margins) ~= "table"
    or type(terminal.margins.top) ~= "number"
    or terminal.margins.top % 1 ~= 0
    or type(terminal.margins.bottom) ~= "number"
    or terminal.margins.bottom % 1 ~= 0
    or terminal.margins.top < 1
    or terminal.margins.bottom > config.rows
    or terminal.margins.top > terminal.margins.bottom
  then
    return config_error("checkpoint scroll region is invalid")
  end
  if type(terminal.modes) ~= "table" then
    return config_error("checkpoint modes are invalid")
  end
  local auto_wrap, auto_wrap_error =
    boolean_byte(terminal.modes.auto_wrap, "checkpoint auto-wrap mode")
  if not auto_wrap then
    return nil, auto_wrap_error
  end
  local cursor_visible, cursor_visible_error =
    boolean_byte(terminal.modes.cursor_visible, "checkpoint cursor visibility mode")
  if not cursor_visible then
    return nil, cursor_visible_error
  end
  local tab_stops, tab_stops_error = encode_tab_stops(terminal.tab_stops, config.columns)
  if not tab_stops then
    return nil, tab_stops_error
  end
  local cursor, cursor_error = encode_cursor(terminal.cursor, config.columns, config.rows)
  if not cursor then
    return nil, cursor_error
  end
  local saved_cursor, saved_cursor_error =
    encode_cursor(terminal.saved_cursor, config.columns, config.rows)
  if not saved_cursor then
    return nil, saved_cursor_error
  end
  local rendition, rendition_error = encode_rendition(terminal.rendition)
  if not rendition then
    return nil, rendition_error
  end
  local saved_rendition, saved_rendition_error = encode_rendition(terminal.saved_rendition)
  if not saved_rendition then
    return nil, saved_rendition_error
  end
  local primary, primary_error =
    encode_screen(terminal.primary_screen, config.columns, config.rows, limits)
  if not primary then
    return nil, primary_error
  end
  local alternate, alternate_error =
    encode_screen(terminal.alternate_screen, config.columns, config.rows, limits)
  if not alternate then
    return nil, alternate_error
  end
  if
    type(terminal.scrollback) ~= "table"
    or type(terminal.scrollback.at) ~= "function"
    or terminal.scrollback.limit ~= config.scrollback_limit
    or type(terminal.scrollback.count) ~= "number"
    or terminal.scrollback.count % 1 ~= 0
    or terminal.scrollback.count < 0
    or terminal.scrollback.count > config.scrollback_limit
    or terminal.scrollback.count > limits.max_scrollback_rows
  then
    return config_error("checkpoint scrollback is invalid or exceeds configured limits")
  end
  local scrollback = { assert(Binary.u32(terminal.scrollback.count)) }
  local scrollback_cells = 0
  for index = 1, terminal.scrollback.count do
    local row, row_error = terminal.scrollback:at(index)
    if not row then
      return nil, row_error
    end
    local row_columns = row.columns
    local row_config, row_config_error = Config.new({ columns = row_columns })
    if not row_config then
      return config_error("checkpoint scrollback row dimensions are invalid", {
        cause = row_config_error,
      })
    end
    scrollback_cells = scrollback_cells + row_config.columns
    if scrollback_cells + cells_per_screen * 2 > limits.max_total_cells then
      return config_error("checkpoint scrollback exceeds configured cell limit")
    end
    local encoded, encoded_error = encode_row(row, nil, limits)
    if not encoded then
      return nil, encoded_error
    end
    scrollback[#scrollback + 1] = encoded
  end
  local parser, parser_error = encode_parser(terminal.parser, limits)
  if not parser then
    return nil, parser_error
  end
  local utf8, utf8_error = encode_utf8(terminal.utf8_decoder)
  if not utf8 then
    return nil, utf8_error
  end
  local payload = table.concat({
    assert(Binary.u16_le(Checkpoint.schema_version)),
    "\1",
    assert(Binary.u16(config.columns)),
    assert(Binary.u16(config.rows)),
    assert(Binary.u32(config.scrollback_limit)),
    terminal.active_buffer == "primary" and "\0" or "\1",
    assert(Binary.u8(auto_wrap)),
    assert(Binary.u8(cursor_visible)),
    assert(Binary.u16(terminal.margins.top)),
    assert(Binary.u16(terminal.margins.bottom)),
    tab_stops,
    cursor,
    saved_cursor,
    rendition,
    saved_rendition,
    primary,
    alternate,
    table.concat(scrollback),
    parser,
    utf8,
  })
  if #payload > limits.max_checkpoint_bytes then
    return config_error("checkpoint payload exceeds configured limit", { length = #payload })
  end
  return payload
end

function Checkpoint.decode(bytes, requested_limits)
  local limits, limits_error = limits_for(requested_limits)
  if not limits then
    return nil, limits_error
  end
  if type(bytes) ~= "string" then
    return config_error("checkpoint input must be bytes", { provided = bytes })
  end
  if #bytes > limits.max_checkpoint_bytes then
    return corrupt("checkpoint payload exceeds configured limit", { length = #bytes })
  end
  local reader = reader_for(bytes)
  local version, version_error = Binary.read_u16_le(bytes, 1)
  if not version then
    return corrupt("truncated checkpoint schema version")
  end
  reader.offset = 3
  if not Checkpoint.supported_schema_versions[version] then
    return nil,
      Errors.new(
        "recording_unsupported_version",
        "unsupported checkpoint schema version",
        { provided = version }
      )
  end
  local profile, profile_error = reader:u8("profile")
  if not profile then
    return nil, profile_error
  end
  if profile ~= 1 then
    return corrupt("checkpoint profile discriminant is invalid", { provided = profile })
  end
  local columns, columns_error = reader:u16("columns")
  if not columns then
    return nil, columns_error
  end
  local rows, rows_error = reader:u16("rows")
  if not rows then
    return nil, rows_error
  end
  local scrollback_limit, scrollback_limit_error = reader:u32("scrollback limit")
  if not scrollback_limit then
    return nil, scrollback_limit_error
  end
  local config, config_error_value = Config.new({
    columns = columns,
    compatibility_profile = "stanczyk-basic-v1",
    rows = rows,
    scrollback_limit = scrollback_limit,
  })
  if not config then
    return corrupt("checkpoint dimensions are invalid", { cause = config_error_value })
  end
  local cells_per_screen = columns * rows
  if
    cells_per_screen > limits.max_cells_per_screen
    or cells_per_screen * 2 > limits.max_total_cells
  then
    return corrupt("checkpoint dimensions exceed configured cell limit")
  end
  local active, active_error = reader:u8("active screen")
  if not active then
    return nil, active_error
  end
  if active > 1 then
    return corrupt("checkpoint active screen discriminant is invalid", { provided = active })
  end
  local auto_wrap_value, auto_wrap_error = reader:u8("auto-wrap mode")
  if not auto_wrap_value then
    return nil, auto_wrap_error
  end
  local auto_wrap, auto_wrap_boolean_error = decode_boolean(auto_wrap_value, "auto-wrap mode")
  if auto_wrap == nil then
    return nil, auto_wrap_boolean_error
  end
  local cursor_visible_value, cursor_visible_error = reader:u8("cursor visibility mode")
  if not cursor_visible_value then
    return nil, cursor_visible_error
  end
  local cursor_visible, cursor_visible_boolean_error =
    decode_boolean(cursor_visible_value, "cursor visibility mode")
  if cursor_visible == nil then
    return nil, cursor_visible_boolean_error
  end
  local margin_top, margin_top_error = reader:u16("scroll-region top")
  if not margin_top then
    return nil, margin_top_error
  end
  local margin_bottom, margin_bottom_error = reader:u16("scroll-region bottom")
  if not margin_bottom then
    return nil, margin_bottom_error
  end
  if margin_top < 1 or margin_bottom > rows or margin_top > margin_bottom then
    return corrupt("checkpoint scroll region is invalid")
  end
  local tab_stops, tab_stops_error = decode_tab_stops(reader, columns)
  if not tab_stops then
    return nil, tab_stops_error
  end
  local cursor, cursor_error = decode_cursor(reader, columns, rows, "active")
  if not cursor then
    return nil, cursor_error
  end
  local saved_cursor, saved_cursor_error = decode_cursor(reader, columns, rows, "saved")
  if not saved_cursor then
    return nil, saved_cursor_error
  end
  local rendition, rendition_error = decode_rendition(reader)
  if not rendition then
    return nil, rendition_error
  end
  local saved_rendition, saved_rendition_error = decode_rendition(reader)
  if not saved_rendition then
    return nil, saved_rendition_error
  end
  local primary, primary_error = decode_screen(reader, columns, rows, limits)
  if not primary then
    return nil, primary_error
  end
  local alternate, alternate_error = decode_screen(reader, columns, rows, limits)
  if not alternate then
    return nil, alternate_error
  end
  local scrollback_count, scrollback_count_error = reader:u32("scrollback count")
  if not scrollback_count then
    return nil, scrollback_count_error
  end
  if scrollback_count > scrollback_limit or scrollback_count > limits.max_scrollback_rows then
    return corrupt(
      "checkpoint scrollback count exceeds configured limit",
      { count = scrollback_count }
    )
  end
  local scrollback = {}
  local scrollback_cells = 0
  for index = 1, scrollback_count do
    local row, row_error = decode_row(reader, version == 1 and columns or nil, limits)
    if not row then
      return nil, row_error
    end
    scrollback_cells = scrollback_cells + row.columns
    if scrollback_cells + cells_per_screen * 2 > limits.max_total_cells then
      return corrupt("checkpoint scrollback exceeds configured cell limit")
    end
    scrollback[index] = row
  end
  local parser, parser_error = decode_parser(reader, limits)
  if not parser then
    return nil, parser_error
  end
  local utf8, utf8_error = decode_utf8(reader)
  if not utf8 then
    return nil, utf8_error
  end
  if reader.offset ~= #bytes + 1 then
    return corrupt("checkpoint payload has trailing bytes", { offset = reader.offset })
  end
  local terminal, terminal_error = Terminal.new({
    columns = columns,
    compatibility_profile = "stanczyk-basic-v1",
    rows = rows,
    scrollback_limit = scrollback_limit,
  })
  if not terminal then
    return corrupt("checkpoint terminal could not be constructed", { cause = terminal_error })
  end
  terminal.active_buffer = active == 0 and "primary" or "alternate"
  terminal.modes = { auto_wrap = auto_wrap, cursor_visible = cursor_visible }
  terminal.margins = { bottom = margin_bottom, top = margin_top }
  terminal.tab_stops = tab_stops
  terminal.cursor = cursor
  terminal.saved_cursor = saved_cursor
  terminal.rendition = rendition
  terminal.saved_rendition = saved_rendition
  restore_rows(terminal.primary_screen.rows, primary, columns)
  restore_rows(terminal.alternate_screen.rows, alternate, columns)
  local restored_scrollback, scrollback_error = restore_scrollback(terminal, scrollback)
  if not restored_scrollback then
    return corrupt("checkpoint scrollback could not be constructed", { cause = scrollback_error })
  end
  terminal.parser.byte_offset = parser.byte_offset
  terminal.parser.csi_intermediates = parser.csi_intermediates
  terminal.parser.csi_parameters = parser.csi_parameters
  terminal.parser.escape_intermediates = parser.escape_intermediates
  terminal.parser.max_csi_bytes = parser.max_csi_bytes
  terminal.parser.max_escape_intermediate_bytes = parser.max_escape_intermediate_bytes
  terminal.parser.max_osc_bytes = parser.max_osc_bytes
  terminal.parser.osc_payload = parser.osc_payload
  terminal.parser.state = parser.state
  terminal.utf8_decoder.codepoint = utf8.codepoint
  terminal.utf8_decoder.minimum = utf8.minimum
  terminal.utf8_decoder.remaining = utf8.remaining
  return terminal
end

return Checkpoint
