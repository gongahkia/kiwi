local assertions = require("support.assertions")
local Checksum = require("recording.checksum")
local Format = require("recording.format")
local Frames = require("recording.frames")
local RecordingWriter = require("recording.writer")
local Event = require("runtime.event")

local function sink()
  local value = { chunks = {}, closed = false, flushes = 0 }
  function value:write(bytes)
    self.chunks[#self.chunks + 1] = bytes
    return true
  end
  function value:flush()
    self.flushes = self.flushes + 1
    return true
  end
  function value:close()
    self.closed = true
    return true
  end
  return value
end

local function bytes(value)
  return table.concat(value.chunks)
end

return {
  {
    name = "recording writer streams canonical header metadata and frames",
    run = function()
      local target = sink()
      local writer = assert(RecordingWriter.new(target, { format = "stanczyk-recording" }))
      local frame = assert(Frames.from_event(assert(Event.output("hello", 17))))
      assertions.truthy(writer:append(frame))
      assertions.equal(1, writer.frame_count)
      assertions.truthy(writer:close())
      assertions.equal(1, target.flushes)
      assertions.truthy(target.closed)

      local recording = bytes(target)
      local preamble, metadata_offset = assert(Format.decode_preamble(recording))
      assertions.equal(1, preamble.major_version)
      assertions.equal(0, preamble.minor_version)
      local metadata, frame_offset =
        assert(Format.decode_metadata(recording, metadata_offset, preamble))
      assertions.equal('{"format":"stanczyk-recording"}', metadata)
      local decoded = assert(Format.decode_frame(recording, frame_offset))
      assertions.equal(Format.kinds.OUTPUT, decoded.kind)
      assertions.equal("hello", decoded.payload)
    end,
  },
  {
    name = "recording writer rejects invalid frames before writing them",
    run = function()
      local target = sink()
      local writer = assert(RecordingWriter.new(target, {}))
      local frame = assert(Frames.from_event(assert(Event.output("safe"))))
      frame.checksum = (frame.checksum + 1) % 0x100000000
      local appended, error_value = writer:append(frame)
      assertions.falsy(appended)
      assertions.equal("config_error", error_value.kind)
      assertions.equal(1, #target.chunks)
      assertions.truthy(writer:close())
    end,
  },
  {
    name = "recording writer finalises failed sinks without retrying close",
    run = function()
      local target = sink()
      local original_flush = target.flush
      target.flush = function(self)
        original_flush(self)
        return nil, "disk full"
      end
      local writer = assert(RecordingWriter.new(target, {}))
      local closed, error_value = writer:close()
      assertions.falsy(closed)
      assertions.equal("recording_io_error", error_value.kind)
      assertions.truthy(target.closed)
      assertions.equal(1, target.flushes)
      closed, error_value = writer:close()
      assertions.falsy(closed)
      assertions.equal("recording_io_error", error_value.kind)
      assertions.equal(1, target.flushes)
    end,
  },
  {
    name = "recording writer closes a sink when initial output fails",
    run = function()
      local target = sink()
      target.write = function()
        return nil, "write failure"
      end
      local writer, error_value = RecordingWriter.new(target, {})
      assertions.falsy(writer)
      assertions.equal("recording_io_error", error_value.kind)
      assertions.truthy(target.closed)
    end,
  },
  {
    name = "recording writer rejects incomplete sink contracts and oversized metadata",
    run = function()
      local writer, error_value = RecordingWriter.new({}, {})
      assertions.falsy(writer)
      assertions.equal("config_error", error_value.kind)
      local target = sink()
      writer, error_value = RecordingWriter.new(target, { value = string.rep("x", 65537) })
      assertions.falsy(writer)
      assertions.equal("config_error", error_value.kind)
    end,
  },
  {
    name = "recording writer preserves the recorded frame checksum",
    run = function()
      local target = sink()
      local writer = assert(RecordingWriter.new(target, {}))
      local frame = assert(Frames.from_event(assert(Event.input("\0\255", 9))))
      assertions.equal(
        frame.checksum,
        assert(Checksum.crc32(assert(Format.frame_checksum_bytes(frame))))
      )
      assertions.truthy(writer:append(frame))
      assertions.truthy(writer:close())
    end,
  },
}
