local assertions = require("support.assertions")
local Checksum = require("recording.checksum")
local Format = require("recording.format")
local Frames = require("recording.frames")
local RecordingReader = require("recording.reader")
local Event = require("runtime.event")

local function source(bytes, chunk_size)
  local value = { bytes = bytes, closed = false, offset = 1, requests = {} }
  function value:read(count)
    self.requests[#self.requests + 1] = count
    if self.offset > #self.bytes then
      return nil
    end
    local finish = math.min(#self.bytes, self.offset + math.min(count, chunk_size or count) - 1)
    local chunk = self.bytes:sub(self.offset, finish)
    self.offset = finish + 1
    return chunk
  end
  function value:close()
    self.closed = true
    return true
  end
  return value
end

local function recording(frames)
  local metadata = '{"format":"stanczyk-recording"}'
  local prefix = assert(Format.encode_preamble({
    flags = 0,
    major_version = 1,
    metadata_checksum = assert(Checksum.crc32(metadata)),
    metadata_length = #metadata,
    minor_version = 0,
  }))
  local encoded = { prefix, metadata }
  for _, frame in ipairs(frames or {}) do
    encoded[#encoded + 1] = assert(Format.encode_frame(frame))
  end
  return table.concat(encoded)
end

return {
  {
    name = "recording reader decodes metadata and frames through bounded reads",
    run = function()
      local output = assert(Frames.from_event(assert(Event.output("hello", 7))))
      local input = assert(Frames.from_event(assert(Event.input("typed", 3))))
      local input_source = source(recording({ output, input }), 2)
      local reader = assert(RecordingReader.new(input_source))
      local metadata = assert(reader:metadata())
      assertions.equal("stanczyk-recording", metadata.format)
      local frame = assert(reader:read_next())
      assertions.equal(Format.kinds.OUTPUT, frame.kind)
      assertions.equal("hello", frame.payload)
      frame = assert(reader:read_next())
      assertions.equal(Format.kinds.INPUT, frame.kind)
      assertions.equal("typed", frame.payload)
      assertions.falsy(reader:read_next())
      assertions.truthy(#input_source.requests > 2)
      assertions.truthy(reader:close())
      assertions.truthy(input_source.closed)
    end,
  },
  {
    name = "recording reader rejects incomplete source contracts and invalid limits",
    run = function()
      local reader, error_value = RecordingReader.new("recording.strec")
      assertions.falsy(reader)
      assertions.equal("config_error", error_value.kind)
      reader, error_value = RecordingReader.new({}, {})
      assertions.falsy(reader)
      assertions.equal("config_error", error_value.kind)
      reader, error_value = RecordingReader.new(source(""), { max_metadata_bytes = -1 })
      assertions.falsy(reader)
      assertions.equal("config_error", error_value.kind)
      reader, error_value = RecordingReader.new(source(""), {
        max_frame_payload_bytes = Format.default_max_frame_payload_bytes + 1,
      })
      assertions.falsy(reader)
      assertions.equal("config_error", error_value.kind)
    end,
  },
  {
    name = "recording reader rejects corruption before payload allocation",
    run = function()
      local bytes = recording()
        .. string.char(Format.kinds.OUTPUT, 0, 0, 0)
        .. "\0\0\0\0"
        .. "\1\0\0\0"
      local reader = assert(RecordingReader.new(source(bytes), { max_frame_payload_bytes = 16 }))
      local frame, error_value = reader:read_next()
      assertions.falsy(frame)
      assertions.equal("recording_corrupt", error_value.kind)
      frame, error_value = reader:read_next()
      assertions.falsy(frame)
      assertions.equal("recording_corrupt", error_value.kind)
      assertions.truthy(reader:close())
    end,
  },
  {
    name = "recording reader reports truncation checksum and source failures precisely",
    run = function()
      local frame = assert(Frames.from_event(assert(Event.output("valid"))))
      local partial = recording({ frame }):sub(1, -2)
      local reader = assert(RecordingReader.new(source(partial)))
      local value, error_value = reader:read_next()
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      local corrupt_frame = assert(Format.encode_frame(frame))
      corrupt_frame = corrupt_frame:sub(1, -5) .. "\0\0\0\0"
      reader = assert(RecordingReader.new(source(recording() .. corrupt_frame)))
      value, error_value = reader:read_next()
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      local failing = source(recording())
      failing.read = function()
        return nil, "device failure"
      end
      reader = assert(RecordingReader.new(failing))
      value, error_value = reader:metadata()
      assertions.falsy(value)
      assertions.equal("recording_io_error", error_value.kind)
      assertions.truthy(reader:close())
    end,
  },
  {
    name = "recording reader close is idempotent and prevents further reads",
    run = function()
      local input_source = source(recording())
      local reader = assert(RecordingReader.new(input_source))
      assertions.truthy(reader:close())
      assertions.truthy(reader:close())
      local value, error_value = reader:metadata()
      assertions.falsy(value)
      assertions.equal("recording_io_error", error_value.kind)
    end,
  },
  {
    name = "recording reader does not retry a failed source close",
    run = function()
      local input_source = source(recording())
      local close_calls = 0
      input_source.close = function()
        close_calls = close_calls + 1
        return nil, "close failure"
      end
      local reader = assert(RecordingReader.new(input_source))
      local value, error_value = reader:close()
      assertions.falsy(value)
      assertions.equal("recording_io_error", error_value.kind)
      value, error_value = reader:close()
      assertions.falsy(value)
      assertions.equal("recording_io_error", error_value.kind)
      assertions.equal(1, close_calls)
    end,
  },
}
