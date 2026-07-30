local Errors = require("runtime.errors")

local Parser = {}
local parser_mt = {}
parser_mt.__index = parser_mt

Parser.contract = {
  feed = "feed(bytes) -> parser_events | nil, error",
  new = "new(config?) -> parser | nil, error",
  snapshot = "snapshot() -> parser_state",
}

local defaults = {
  max_csi_bytes = 128,
  max_escape_intermediate_bytes = 4,
  max_osc_bytes = 4096,
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function invariant_error(message, detail)
  return nil, Errors.new("internal_invariant_error", message, detail)
end

local function bounded_integer(value, name, maximum)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > maximum then
    return config_error(name .. " must be an integer from 1 to " .. maximum, { provided = value })
  end
  return value
end

local function is_c0(byte)
  return byte <= 0x1F
end

local function is_cancel(byte)
  return byte == 0x18 or byte == 0x1A
end

local function is_escape_intermediate(byte)
  return byte >= 0x20 and byte <= 0x2F
end

local function is_escape_final(byte)
  return byte >= 0x30 and byte <= 0x7E
end

local function is_csi_parameter(byte)
  return byte >= 0x30 and byte <= 0x3F
end

local function is_csi_final(byte)
  return byte >= 0x40 and byte <= 0x7E
end

local function emit(parser, events, kind, event)
  event.kind = kind
  event.offset = parser.byte_offset
  events[#events + 1] = event
end

local function clear_csi(parser)
  parser.csi_intermediates = ""
  parser.csi_parameters = ""
end

local function clear_escape(parser)
  parser.escape_intermediates = ""
end

local function clear_osc(parser)
  parser.osc_payload = ""
end

local function start_escape(parser)
  clear_csi(parser)
  clear_escape(parser)
  clear_osc(parser)
  parser.state = "escape"
end

local function cancel(parser, events, reason, byte)
  emit(parser, events, "malformed", { byte = byte, reason = reason, state = parser.state })
  clear_csi(parser)
  clear_escape(parser)
  clear_osc(parser)
  parser.state = "ground"
end

local function restart_escape(parser, events)
  cancel(parser, events, "restarted", 0x1B)
  start_escape(parser)
end

local function execute_control(parser, events, byte)
  emit(parser, events, "control", { byte = byte })
end

local function append_escape_intermediate(parser, events, byte)
  if #parser.escape_intermediates >= parser.max_escape_intermediate_bytes then
    emit(
      parser,
      events,
      "malformed",
      { byte = byte, reason = "escape_intermediate_limit", state = parser.state }
    )
    clear_escape(parser)
    parser.state = "escape_ignore"
    return false
  end
  parser.escape_intermediates = parser.escape_intermediates .. string.char(byte)
  return true
end

local function append_csi(parser, events, field, byte)
  if #parser.csi_parameters + #parser.csi_intermediates >= parser.max_csi_bytes then
    emit(parser, events, "malformed", { byte = byte, reason = "csi_limit", state = parser.state })
    clear_csi(parser)
    parser.state = "csi_ignore"
    return false
  end
  parser[field] = parser[field] .. string.char(byte)
  return true
end

local function append_osc(parser, events, byte)
  if #parser.osc_payload >= parser.max_osc_bytes then
    emit(parser, events, "malformed", { byte = byte, reason = "osc_limit", state = parser.state })
    clear_osc(parser)
    parser.state = "osc_ignore"
    return false
  end
  parser.osc_payload = parser.osc_payload .. string.char(byte)
  return true
end

local function dispatch_escape(parser, events, byte)
  emit(parser, events, "esc", {
    final = byte,
    intermediates = parser.escape_intermediates,
  })
  clear_escape(parser)
  parser.state = "ground"
end

local function dispatch_csi(parser, events, byte)
  emit(parser, events, "csi", {
    final = byte,
    intermediates = parser.csi_intermediates,
    parameters = parser.csi_parameters,
  })
  clear_csi(parser)
  parser.state = "ground"
end

local function dispatch_osc(parser, events, terminator)
  emit(parser, events, "osc", {
    payload = parser.osc_payload,
    terminator = terminator,
  })
  clear_osc(parser)
  parser.state = "ground"
end

local function handle_ground(parser, events, byte)
  if byte == 0x1B then
    start_escape(parser)
  elseif is_c0(byte) then
    execute_control(parser, events, byte)
  elseif byte ~= 0x7F then
    emit(parser, events, "print", { byte = byte })
  end
end

local function handle_escape(parser, events, byte)
  if byte == 0x1B then
    restart_escape(parser, events)
  elseif is_cancel(byte) then
    cancel(parser, events, "cancelled", byte)
  elseif is_c0(byte) then
    execute_control(parser, events, byte)
  elseif byte == 0x5B then
    clear_csi(parser)
    parser.state = "csi_entry"
  elseif byte == 0x5D then
    clear_osc(parser)
    parser.state = "osc_string"
  elseif is_escape_intermediate(byte) then
    append_escape_intermediate(parser, events, byte)
  elseif is_escape_final(byte) then
    dispatch_escape(parser, events, byte)
  else
    emit(
      parser,
      events,
      "malformed",
      { byte = byte, reason = "invalid_escape", state = parser.state }
    )
    clear_escape(parser)
    parser.state = "escape_ignore"
  end
end

local function handle_escape_ignore(parser, events, byte)
  if byte == 0x1B then
    restart_escape(parser, events)
  elseif is_cancel(byte) then
    cancel(parser, events, "cancelled", byte)
  elseif is_c0(byte) then
    execute_control(parser, events, byte)
  elseif is_escape_final(byte) then
    parser.state = "ground"
  end
end

local function handle_csi_entry(parser, events, byte)
  if byte == 0x1B then
    restart_escape(parser, events)
  elseif is_cancel(byte) then
    cancel(parser, events, "cancelled", byte)
  elseif is_c0(byte) then
    execute_control(parser, events, byte)
  elseif is_csi_parameter(byte) then
    if append_csi(parser, events, "csi_parameters", byte) then
      parser.state = "csi_parameter"
    end
  elseif is_escape_intermediate(byte) then
    if append_csi(parser, events, "csi_intermediates", byte) then
      parser.state = "csi_intermediate"
    end
  elseif is_csi_final(byte) then
    dispatch_csi(parser, events, byte)
  else
    emit(parser, events, "malformed", { byte = byte, reason = "invalid_csi", state = parser.state })
    clear_csi(parser)
    parser.state = "csi_ignore"
  end
end

local function handle_csi_parameter(parser, events, byte)
  if byte == 0x1B then
    restart_escape(parser, events)
  elseif is_cancel(byte) then
    cancel(parser, events, "cancelled", byte)
  elseif is_c0(byte) then
    execute_control(parser, events, byte)
  elseif is_csi_parameter(byte) then
    append_csi(parser, events, "csi_parameters", byte)
  elseif is_escape_intermediate(byte) then
    if append_csi(parser, events, "csi_intermediates", byte) then
      parser.state = "csi_intermediate"
    end
  elseif is_csi_final(byte) then
    dispatch_csi(parser, events, byte)
  else
    emit(parser, events, "malformed", { byte = byte, reason = "invalid_csi", state = parser.state })
    clear_csi(parser)
    parser.state = "csi_ignore"
  end
end

local function handle_csi_intermediate(parser, events, byte)
  if byte == 0x1B then
    restart_escape(parser, events)
  elseif is_cancel(byte) then
    cancel(parser, events, "cancelled", byte)
  elseif is_c0(byte) then
    execute_control(parser, events, byte)
  elseif is_escape_intermediate(byte) then
    append_csi(parser, events, "csi_intermediates", byte)
  elseif is_csi_final(byte) then
    dispatch_csi(parser, events, byte)
  else
    emit(parser, events, "malformed", { byte = byte, reason = "invalid_csi", state = parser.state })
    clear_csi(parser)
    parser.state = "csi_ignore"
  end
end

local function handle_csi_ignore(parser, events, byte)
  if byte == 0x1B then
    restart_escape(parser, events)
  elseif is_cancel(byte) then
    cancel(parser, events, "cancelled", byte)
  elseif is_c0(byte) then
    execute_control(parser, events, byte)
  elseif is_csi_final(byte) then
    parser.state = "ground"
  end
end

local function handle_osc_string(parser, events, byte)
  if byte == 0x1B then
    parser.state = "osc_escape"
  elseif byte == 0x07 then
    dispatch_osc(parser, events, "bel")
  elseif is_cancel(byte) then
    cancel(parser, events, "cancelled", byte)
  else
    append_osc(parser, events, byte)
  end
end

local function handle_osc_escape(parser, events, byte)
  if byte == 0x5C then
    dispatch_osc(parser, events, "st")
  elseif byte == 0x1B then
    emit(
      parser,
      events,
      "malformed",
      { byte = byte, reason = "osc_escape_restarted", state = parser.state }
    )
  elseif is_cancel(byte) then
    cancel(parser, events, "cancelled", byte)
  else
    emit(
      parser,
      events,
      "malformed",
      { byte = byte, reason = "invalid_osc_terminator", state = parser.state }
    )
    parser.state = "osc_string"
    handle_osc_string(parser, events, byte)
  end
end

local function handle_osc_ignore(parser, events, byte)
  if byte == 0x1B then
    parser.state = "osc_ignore_escape"
  elseif byte == 0x07 or is_cancel(byte) then
    clear_osc(parser)
    parser.state = "ground"
  end
end

local function handle_osc_ignore_escape(parser, events, byte)
  if byte == 0x5C then
    clear_osc(parser)
    parser.state = "ground"
  elseif byte == 0x1B then
    parser.state = "osc_ignore_escape"
  else
    parser.state = "osc_ignore"
  end
end

local handlers = {
  csi_entry = handle_csi_entry,
  csi_ignore = handle_csi_ignore,
  csi_intermediate = handle_csi_intermediate,
  csi_parameter = handle_csi_parameter,
  escape = handle_escape,
  escape_ignore = handle_escape_ignore,
  ground = handle_ground,
  osc_escape = handle_osc_escape,
  osc_ignore = handle_osc_ignore,
  osc_ignore_escape = handle_osc_ignore_escape,
  osc_string = handle_osc_string,
}

function Parser.new(config)
  if config == nil then
    config = {}
  end
  if type(config) ~= "table" then
    return config_error("parser config must be a table")
  end
  for name in pairs(config) do
    if defaults[name] == nil then
      return config_error("unknown parser config option", { option = name })
    end
  end
  local values = {}
  for name, default in pairs(defaults) do
    local requested = config[name]
    if requested == nil then
      requested = default
    end
    local value, value_error = bounded_integer(requested, name, 65536)
    if not value then
      return nil, value_error
    end
    values[name] = value
  end
  return setmetatable({
    byte_offset = 0,
    csi_intermediates = "",
    csi_parameters = "",
    escape_intermediates = "",
    max_csi_bytes = values.max_csi_bytes,
    max_escape_intermediate_bytes = values.max_escape_intermediate_bytes,
    max_osc_bytes = values.max_osc_bytes,
    osc_payload = "",
    state = "ground",
  }, parser_mt)
end

function parser_mt:feed(bytes)
  if type(bytes) ~= "string" then
    return config_error("parser input must be bytes")
  end
  local events = {}
  for index = 1, #bytes do
    local handler = handlers[self.state]
    if not handler then
      return invariant_error("parser entered an unknown state", { state = self.state })
    end
    local state_before = self.state
    local first_event = #events + 1
    handler(self, events, bytes:byte(index))
    for event_index = first_event, #events do
      events[event_index].state_after = self.state
      events[event_index].state_before = state_before
    end
    self.byte_offset = self.byte_offset + 1
  end
  return events
end

function parser_mt:snapshot()
  return {
    byte_offset = self.byte_offset,
    csi_intermediates = self.csi_intermediates,
    csi_parameters = self.csi_parameters,
    escape_intermediates = self.escape_intermediates,
    max_csi_bytes = self.max_csi_bytes,
    max_escape_intermediate_bytes = self.max_escape_intermediate_bytes,
    max_osc_bytes = self.max_osc_bytes,
    osc_payload = self.osc_payload,
    state = self.state,
  }
end

return Parser
