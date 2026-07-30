local Binary = require("recording.binary")
local Checksum = require("recording.checksum")
local Errors = require("runtime.errors")
local Format = require("recording.format")
local Metadata = require("recording.metadata")
local Event = require("runtime.event")

local Frames = {}

Frames.contract = {
  from_event = "from_event(event) -> recording_frame | nil, error",
  to_event = "to_event(recording_frame) -> event | nil, error",
}

local function corrupt_error(message, detail)
  return nil, Errors.new("recording_corrupt", message, detail)
end

local function frame(kind, delta_us, payload)
  local recorded = {
    delta_us = delta_us,
    flags = 0,
    kind = kind,
    payload = payload,
    payload_length = #payload,
    reserved = 0,
  }
  local checksum_bytes, bytes_error = Format.frame_checksum_bytes(recorded)
  if not checksum_bytes then
    return nil, bytes_error
  end
  local checksum, checksum_error = Checksum.crc32(checksum_bytes)
  if not checksum then
    return nil, checksum_error
  end
  recorded.checksum = checksum
  return recorded
end

local function resize_payload(event)
  return assert(Binary.u32(event.columns))
    .. assert(Binary.u32(event.rows))
    .. assert(Binary.u32(event.pixel_width))
    .. assert(Binary.u32(event.pixel_height))
end

local function valid_frame(frame_value)
  local checksum_bytes, bytes_error = Format.frame_checksum_bytes(frame_value)
  if not checksum_bytes then
    return nil, bytes_error
  end
  local actual_checksum, checksum_error = Checksum.crc32(checksum_bytes)
  if not actual_checksum then
    return nil, checksum_error
  end
  if frame_value.checksum ~= actual_checksum then
    return corrupt_error("recording frame checksum mismatch")
  end
  return true
end

function Frames.from_event(event)
  local normalised, event_error = Event.validate(event)
  if not normalised then
    return nil, event_error
  end
  if normalised.kind == "output" then
    return frame(Format.kinds.OUTPUT, normalised.delta_us, normalised.data)
  end
  if normalised.kind == "input" then
    return frame(Format.kinds.INPUT, normalised.delta_us, normalised.data)
  end
  if normalised.kind == "resize" then
    return frame(Format.kinds.RESIZE, normalised.delta_us, resize_payload(normalised))
  end
  if normalised.kind == "mark" then
    local payload, payload_error =
      Metadata.encode({ data = normalised.data or {}, name = normalised.name })
    if not payload then
      return nil, payload_error
    end
    return frame(Format.kinds.MARK, normalised.delta_us, payload)
  end
  if normalised.kind == "clock_advance" then
    return frame(Format.kinds.CLOCK_ADVANCE, normalised.delta_us, "")
  end
  return nil,
    Errors.new(
      "config_error",
      "event kind is not recordable in this slice",
      { kind = normalised.kind }
    )
end

function Frames.to_event(frame_value)
  if type(frame_value) ~= "table" then
    return corrupt_error("recording frame must be a table")
  end
  local valid, frame_error = valid_frame(frame_value)
  if not valid then
    return nil, frame_error
  end
  if frame_value.kind == Format.kinds.OUTPUT then
    return Event.output(frame_value.payload, frame_value.delta_us)
  end
  if frame_value.kind == Format.kinds.INPUT then
    return Event.input(frame_value.payload, frame_value.delta_us)
  end
  if frame_value.kind == Format.kinds.RESIZE then
    if #frame_value.payload ~= 16 then
      return corrupt_error("recording resize payload must be exactly 16 bytes")
    end
    local columns, index = assert(Binary.read_u32(frame_value.payload))
    local rows
    rows, index = assert(Binary.read_u32(frame_value.payload, index))
    local pixel_width
    pixel_width, index = assert(Binary.read_u32(frame_value.payload, index))
    local pixel_height
    pixel_height = assert(Binary.read_u32(frame_value.payload, index))
    local event, event_error =
      Event.resize(columns, rows, pixel_width, pixel_height, frame_value.delta_us)
    if not event then
      return corrupt_error("recording resize payload is invalid", { cause = event_error })
    end
    return event
  end
  if frame_value.kind == Format.kinds.MARK then
    local mark, mark_error = Metadata.decode(frame_value.payload)
    if not mark then
      return nil, mark_error
    end
    if type(mark.name) ~= "string" or mark.name == "" or type(mark.data) ~= "table" then
      return corrupt_error("recording mark payload is invalid")
    end
    local event, event_error = Event.mark(mark.name, mark.data, frame_value.delta_us)
    if not event then
      return corrupt_error("recording mark payload is invalid", { cause = event_error })
    end
    return event
  end
  if frame_value.kind == Format.kinds.CLOCK_ADVANCE then
    if frame_value.payload ~= "" then
      return corrupt_error("recording clock-advance payload must be empty")
    end
    return Event.clock_advance(frame_value.delta_us)
  end
  return corrupt_error("recording frame kind is not replayable", { kind = frame_value.kind })
end

return Frames
