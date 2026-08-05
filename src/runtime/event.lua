local Errors = require("runtime.errors")

local Event = {}

Event.contract = {
  output = "output(bytes, delta_us?, source_sequence?) -> event | nil, error",
  input = "input(bytes, delta_us?, source_sequence?) -> event | nil, error",
  resize = "resize(columns, rows, pixel_width?, pixel_height?, delta_us?, source_sequence?) -> event | nil, error",
  mark = "mark(name, data?, delta_us?, source_sequence?) -> event | nil, error",
  status = "status(state, detail?, delta_us?, source_sequence?) -> event | nil, error",
  exit = "exit(code?, signal?, delta_us?, source_sequence?) -> event | nil, error",
  clock_advance = "clock_advance(delta_us, source_sequence?) -> event | nil, error",
  validate = "validate(event) -> normalised_event | nil, error",
}

local MAX_U32 = 4294967295
local event_kinds = {
  clock_advance = true,
  exit = true,
  input = true,
  mark = true,
  output = true,
  resize = true,
  status = true,
}

local function uint32(value, name)
  if type(value) ~= "number" or value < 0 or value > MAX_U32 or value % 1 ~= 0 then
    return nil, Errors.new("backend_protocol_error", name .. " must be an unsigned 32-bit integer")
  end
  return value
end

local function optional_sequence(value)
  if value == nil then
    return nil
  end
  return uint32(value, "source_sequence")
end

local function base(kind, delta_us, source_sequence)
  if not event_kinds[kind] then
    return nil, Errors.new("backend_protocol_error", "unknown event kind")
  end
  local valid_delta, delta_error = uint32(delta_us or 0, "delta_us")
  if not valid_delta then
    return nil, delta_error
  end
  local valid_sequence, sequence_error = optional_sequence(source_sequence)
  if sequence_error then
    return nil, sequence_error
  end
  return {
    kind = kind,
    delta_us = valid_delta,
    source_sequence = valid_sequence,
  }
end

local function bytes(kind, data, delta_us, source_sequence)
  if type(data) ~= "string" then
    return nil, Errors.new("backend_protocol_error", kind .. " event data must be bytes")
  end
  local event, event_error = base(kind, delta_us, source_sequence)
  if not event then
    return nil, event_error
  end
  event.data = data
  return event
end

function Event.output(data, delta_us, source_sequence)
  return bytes("output", data, delta_us, source_sequence)
end

function Event.input(data, delta_us, source_sequence)
  return bytes("input", data, delta_us, source_sequence)
end

function Event.resize(columns, rows, pixel_width, pixel_height, delta_us, source_sequence)
  local valid_columns, column_error = uint32(columns, "columns")
  if not valid_columns or valid_columns == 0 then
    return nil, column_error or Errors.new("backend_protocol_error", "columns must be positive")
  end
  local valid_rows, row_error = uint32(rows, "rows")
  if not valid_rows or valid_rows == 0 then
    return nil, row_error or Errors.new("backend_protocol_error", "rows must be positive")
  end
  local valid_width, width_error = uint32(pixel_width or 0, "pixel_width")
  if not valid_width then
    return nil, width_error
  end
  local valid_height, height_error = uint32(pixel_height or 0, "pixel_height")
  if not valid_height then
    return nil, height_error
  end
  local event, event_error = base("resize", delta_us, source_sequence)
  if not event then
    return nil, event_error
  end
  event.columns = valid_columns
  event.rows = valid_rows
  event.pixel_width = valid_width
  event.pixel_height = valid_height
  return event
end

function Event.mark(name, data, delta_us, source_sequence)
  if type(name) ~= "string" or name == "" then
    return nil, Errors.new("backend_protocol_error", "mark name must be a non-empty string")
  end
  if data ~= nil and type(data) ~= "table" then
    return nil, Errors.new("backend_protocol_error", "mark data must be a table")
  end
  local event, event_error = base("mark", delta_us, source_sequence)
  if not event then
    return nil, event_error
  end
  event.name = name
  event.data = data
  return event
end

function Event.status(state, detail, delta_us, source_sequence)
  if type(state) ~= "string" or state == "" then
    return nil, Errors.new("backend_protocol_error", "status state must be a non-empty string")
  end
  if detail ~= nil and type(detail) ~= "table" then
    return nil, Errors.new("backend_protocol_error", "status detail must be a table")
  end
  local event, event_error = base("status", delta_us, source_sequence)
  if not event then
    return nil, event_error
  end
  event.state = state
  event.detail = detail
  return event
end

function Event.exit(code, signal, delta_us, source_sequence)
  if code ~= nil and (type(code) ~= "number" or code % 1 ~= 0) then
    return nil, Errors.new("backend_protocol_error", "exit code must be an integer")
  end
  if signal ~= nil and (type(signal) ~= "number" or signal % 1 ~= 0 or signal < 0) then
    return nil, Errors.new("backend_protocol_error", "exit signal must be a non-negative integer")
  end
  local event, event_error = base("exit", delta_us, source_sequence)
  if not event then
    return nil, event_error
  end
  event.code = code
  event.signal = signal
  return event
end

function Event.clock_advance(delta_us, source_sequence)
  return base("clock_advance", delta_us, source_sequence)
end

function Event.validate(value)
  if type(value) ~= "table" then
    return nil, Errors.new("backend_protocol_error", "event must be a table")
  end
  local kind = value.kind
  if kind == "output" then
    return Event.output(value.data, value.delta_us, value.source_sequence)
  elseif kind == "input" then
    return Event.input(value.data, value.delta_us, value.source_sequence)
  elseif kind == "resize" then
    return Event.resize(
      value.columns,
      value.rows,
      value.pixel_width,
      value.pixel_height,
      value.delta_us,
      value.source_sequence
    )
  elseif kind == "mark" then
    return Event.mark(value.name, value.data, value.delta_us, value.source_sequence)
  elseif kind == "status" then
    return Event.status(value.state, value.detail, value.delta_us, value.source_sequence)
  elseif kind == "exit" then
    return Event.exit(value.code, value.signal, value.delta_us, value.source_sequence)
  elseif kind == "clock_advance" then
    return Event.clock_advance(value.delta_us, value.source_sequence)
  end
  return nil, Errors.new("backend_protocol_error", "unknown event kind")
end

return Event
