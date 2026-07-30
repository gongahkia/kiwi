local assertions = require("support.assertions")
local Backend = require("backend.interface")
local Checksum = require("recording.checksum")
local Format = require("recording.format")
local Frames = require("recording.frames")
local Replay = require("backend.replay")
local Event = require("runtime.event")

local function source(bytes, chunk_size)
  local value = { bytes = bytes, closed = false, offset = 1 }
  function value:read(count)
    if self.offset > #self.bytes then
      return nil
    end
    local finish = math.min(#self.bytes, self.offset + math.min(count, chunk_size or count) - 1)
    local output = self.bytes:sub(self.offset, finish)
    self.offset = finish + 1
    return output
  end
  function value:close()
    self.closed = true
    return true
  end
  return value
end

local function recording(frames)
  local metadata = '{"format":"stanczyk-recording"}'
  local preamble = assert(Format.encode_preamble({
    flags = 0,
    major_version = 1,
    metadata_checksum = assert(Checksum.crc32(metadata)),
    metadata_length = #metadata,
    minor_version = 0,
  }))
  local chunks = { preamble, metadata }
  for _, frame in ipairs(frames) do
    chunks[#chunks + 1] = assert(Format.encode_frame(frame))
  end
  return table.concat(chunks)
end

return {
  {
    name = "replay backend controls deterministic playback without a wall clock",
    run = function()
      local first = assert(Frames.from_event(assert(Event.output("first", 10))))
      local second = assert(Frames.from_event(assert(Event.resize(100, 30, 0, 0, 5))))
      local input_source = source(recording({ first, second }), 3)
      local replay = assert(Replay.new(input_source))
      assertions.equal(replay, assert(Backend.validate(replay)))
      assertions.truthy(replay:start())
      assertions.equal(0, #assert(replay:poll(9)))
      assertions.equal(0, replay:status().elapsed_terminal_us)
      local events = assert(replay:poll(1))
      assertions.equal(1, #events)
      assertions.equal("output", events[1].kind)
      assertions.equal("first", events[1].data)
      assertions.equal(10, replay:status().elapsed_terminal_us)
      assertions.truthy(replay:pause())
      assertions.equal(0, #assert(replay:poll(1000)))
      assertions.equal(10, replay:status().elapsed_terminal_us)
      assertions.truthy(replay:play())
      assertions.truthy(replay:set_speed(2))
      events = assert(replay:poll(2))
      assertions.equal(0, #events)
      events = assert(replay:poll(1))
      assertions.equal(1, #events)
      assertions.equal("resize", events[1].kind)
      assertions.equal(15, replay:status().elapsed_terminal_us)
      assertions.equal("exhausted", replay:status().state)
      assertions.truthy(replay:stop("test complete"))
      assertions.truthy(input_source.closed)
    end,
  },
  {
    name = "replay backend uses injected advances and bounded event batches",
    run = function()
      local frames = {
        assert(Frames.from_event(assert(Event.output("a", 0)))),
        assert(Frames.from_event(assert(Event.output("b", 0)))),
        assert(Frames.from_event(assert(Event.output("c", 0)))),
      }
      local replay =
        assert(Replay.new(source(recording(frames)), { max_events_per_poll = 1, speed = 0.5 }))
      assertions.truthy(replay:start())
      assertions.equal(1, #assert(replay:poll(0)))
      assertions.equal(1, replay:status().current_frame)
      assertions.equal(1, #assert(replay:poll(0)))
      assertions.equal(1, #assert(replay:poll(0)))
      assertions.equal(3, replay:status().current_frame)
      assertions.equal(0, #assert(replay:poll(0)))
      assertions.equal("exhausted", replay:status().state)

      local delayed = assert(Replay.new(
        source(recording({
          assert(Frames.from_event(assert(Event.output("later", 10)))),
        })),
        { speed = 0.5 }
      ))
      assertions.truthy(delayed:start())
      assertions.equal(0, #assert(delayed:poll(19)))
      assertions.equal(1, #assert(delayed:poll(1)))
    end,
  },
  {
    name = "replay backend rejects unsupported controls and invalid configuration",
    run = function()
      local value, error_value = Replay.new(source(recording({})), { speed = 0 })
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      local replay = assert(Replay.new(source(recording({}))))
      value, error_value = replay:poll(0)
      assertions.falsy(value)
      assertions.equal("backend_unavailable", error_value.kind)
      assertions.truthy(replay:start())
      value, error_value = replay:send_input("ignored")
      assertions.falsy(value)
      assertions.equal("backend_unavailable", error_value.kind)
      value, error_value = replay:resize(80, 24)
      assertions.falsy(value)
      assertions.equal("backend_unavailable", error_value.kind)
      value, error_value = replay:set_speed(0)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      assertions.truthy(replay:stop())
      value, error_value = replay:poll(0)
      assertions.falsy(value)
      assertions.equal("backend_exited", error_value.kind)
    end,
  },
  {
    name = "replay backend skips unknown noncritical frames but rejects malformed known frames",
    run = function()
      local unknown = {
        checksum = 0,
        delta_us = 0,
        flags = 0,
        kind = 0x80,
        payload = "extension",
        payload_length = #"extension",
        reserved = 0,
      }
      unknown.checksum = assert(Checksum.crc32(assert(Format.frame_checksum_bytes(unknown))))
      local replay = assert(Replay.new(source(recording({
        unknown,
        assert(Frames.from_event(assert(Event.output("known", 0)))),
      }))))
      assertions.truthy(replay:start())
      local events = assert(replay:poll(0))
      assertions.equal(1, #events)
      assertions.equal("known", events[1].data)

      local malformed = assert(Frames.from_event(assert(Event.resize(80, 24, 0, 0, 0))))
      malformed.payload = "invalid"
      malformed.payload_length = #malformed.payload
      malformed.checksum = assert(Checksum.crc32(assert(Format.frame_checksum_bytes(malformed))))
      replay = assert(Replay.new(source(recording({ malformed }))))
      assertions.truthy(replay:start())
      local value, error_value = replay:poll(0)
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
    end,
  },
}
