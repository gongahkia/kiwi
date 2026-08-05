local assertions = require("support.assertions")
local Checksum = require("recording.checksum")
local Format = require("recording.format")
local Frames = require("recording.frames")
local Event = require("runtime.event")

local function resign(frame)
  frame.checksum = assert(Checksum.crc32(assert(Format.frame_checksum_bytes(frame))))
end

local function round_trip(event)
  local frame = assert(Frames.from_event(event))
  local bytes = assert(Format.encode_frame(frame))
  local decoded_frame = assert(Format.decode_frame(bytes))
  return decoded_frame, assert(Frames.to_event(decoded_frame))
end

return {
  {
    name = "recording frames preserve output input and clock bytes",
    run = function()
      local frame, event = round_trip(assert(Event.output("\0\255\n", 7, 9)))
      assertions.equal(Format.kinds.OUTPUT, frame.kind)
      assertions.equal("output", event.kind)
      assertions.equal("\0\255\n", event.data)
      assertions.equal(7, event.delta_us)

      frame, event = round_trip(assert(Event.input("typed", 8, 10)))
      assertions.equal(Format.kinds.INPUT, frame.kind)
      assertions.equal("input", event.kind)
      assertions.equal("typed", event.data)

      frame, event = round_trip(assert(Event.clock_advance(0xFFFFFFFF, 11)))
      assertions.equal(Format.kinds.CLOCK_ADVANCE, frame.kind)
      assertions.equal("clock_advance", event.kind)
      assertions.equal(0xFFFFFFFF, event.delta_us)
    end,
  },
  {
    name = "recording frames preserve resize and canonical mark payloads",
    run = function()
      local frame, event = round_trip(assert(Event.resize(80, 24, 800, 600, 9)))
      assertions.equal(Format.kinds.RESIZE, frame.kind)
      assertions.equal("\0\0\0P\0\0\0\24\0\0\3 \0\0\2X", frame.payload)
      assertions.equal(80, event.columns)
      assertions.equal(24, event.rows)
      assertions.equal(800, event.pixel_width)
      assertions.equal(600, event.pixel_height)

      frame, event = round_trip(assert(Event.mark("before_demo", { path = "/tmp" }, 10)))
      assertions.equal(Format.kinds.MARK, frame.kind)
      assertions.equal('{"data":{"path":"/tmp"},"name":"before_demo"}', frame.payload)
      assertions.equal("mark", event.kind)
      assertions.equal("before_demo", event.name)
      assertions.equal("/tmp", event.data.path)
    end,
  },
  {
    name = "recording frames reject invalid resize mark and checkpoint payloads",
    run = function()
      local frame = assert(Frames.from_event(assert(Event.resize(80, 24, 0, 0, 0))))
      frame.payload = frame.payload:sub(1, 15)
      frame.payload_length = #frame.payload
      resign(frame)
      local value, error_value = Frames.to_event(frame)
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      frame = assert(Frames.from_event(assert(Event.mark("mark", {}, 0))))
      frame.payload = '{"name":"mark"}'
      frame.payload_length = #frame.payload
      resign(frame)
      value, error_value = Frames.to_event(frame)
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      value, error_value = Frames.to_event({
        checksum = 0,
        delta_us = 0,
        flags = 0,
        kind = Format.kinds.CHECKPOINT,
        payload = "",
        payload_length = 0,
        reserved = 0,
      })
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
    end,
  },
}
