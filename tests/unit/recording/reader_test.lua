local assertions = require("support.assertions")
local Checksum = require("recording.checksum")
local Format = require("recording.format")
local Frames = require("recording.frames")
local RecordingReader = require("recording.reader")
local Event = require("runtime.event")

local function source(bytes, chunk_size, seekable)
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
  if seekable then
    function value:seek(offset)
      if offset < 0 or offset > #self.bytes then
        return nil, "invalid offset"
      end
      self.offset = offset + 1
      return offset
    end
  end
  return value
end

local function recording(frames, options)
  options = options or {}
  local metadata = options.metadata or '{"format":"stanczyk-recording"}'
  local prefix = assert(Format.encode_preamble({
    flags = 0,
    major_version = options.major_version or 1,
    metadata_checksum = assert(Checksum.crc32(metadata)),
    metadata_length = #metadata,
    minor_version = options.minor_version or 0,
  }))
  local encoded = { prefix, metadata }
  for _, frame in ipairs(frames or {}) do
    encoded[#encoded + 1] = assert(Format.encode_frame(frame))
  end
  return table.concat(encoded)
end

local function raw_frame(kind, payload)
  local frame = {
    checksum = 0,
    delta_us = 0,
    flags = 0,
    kind = kind,
    payload = payload,
    payload_length = #payload,
    reserved = 0,
  }
  frame.checksum = assert(Checksum.crc32(assert(Format.frame_checksum_bytes(frame))))
  return frame
end

local function read_to_end(reader)
  while true do
    local frame, error_value = reader:read_next()
    if not frame then
      return error_value
    end
  end
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
    name = "recording reader seeks only to framed offsets on seekable sources",
    run = function()
      local output = assert(Frames.from_event(assert(Event.output("one", 0))))
      local input = assert(Frames.from_event(assert(Event.input("two", 0))))
      local input_source = source(recording({ output, input }), 3, true)
      local reader = assert(RecordingReader.new(input_source))
      local first_offset = assert(reader:position())
      assertions.equal(Format.preamble_size + #'{"format":"stanczyk-recording"}', first_offset)
      assertions.equal("one", assert(reader:read_next()).payload)
      assertions.truthy(reader:seek_frame(first_offset))
      assertions.equal("one", assert(reader:read_next()).payload)
      local value, error_value = reader:seek_frame(first_offset - 1)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      assertions.truthy(reader:close())
    end,
  },
  {
    name = "recording reader rejects unsupported major versions before metadata reads",
    run = function()
      local input_source = source(recording({}, { major_version = 2 }))
      local reader = assert(RecordingReader.new(input_source))
      local value, error_value = reader:metadata()
      assertions.falsy(value)
      assertions.equal("recording_unsupported_version", error_value.kind)
      assertions.equal(Format.preamble_size + 1, input_source.offset)
      assertions.truthy(reader:close())
    end,
  },
  {
    name = "recording reader accepts compatible minor extensions without interpreting them",
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
      local reader = assert(RecordingReader.new(source(recording({ unknown }, {
        metadata = '{"extension":"enabled","format":"stanczyk-recording"}',
        minor_version = 1,
      }))))
      local metadata = assert(reader:metadata())
      assertions.equal("enabled", metadata.extension)
      assertions.equal(1, assert(reader:version()).recording_minor_version)
      local frame = assert(reader:read_next())
      assertions.equal(0x80, frame.kind)
      assertions.equal("extension", frame.payload)
      assertions.truthy(reader:close())
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
  {
    name = "recording reader rejects truncation inside every defined frame kind",
    run = function()
      local kinds = {
        Format.kinds.OUTPUT,
        Format.kinds.INPUT,
        Format.kinds.RESIZE,
        Format.kinds.MARK,
        Format.kinds.CHECKPOINT,
        Format.kinds.STATUS,
        Format.kinds.EXIT,
        Format.kinds.CLOCK_ADVANCE,
      }
      local frames = {}
      for _, kind in ipairs(kinds) do
        frames[#frames + 1] = raw_frame(kind, "frame" .. string.char(kind))
      end
      local bytes = recording(frames)
      local frame_offset = Format.preamble_size + #'{"format":"stanczyk-recording"}'
      for _, frame in ipairs(frames) do
        local encoded = assert(Format.encode_frame(frame))
        for length = 1, #encoded - 1 do
          local reader = assert(RecordingReader.new(source(bytes:sub(1, frame_offset + length))))
          local error_value = read_to_end(reader)
          assertions.equal(
            "recording_corrupt",
            error_value and error_value.kind,
            "kind=" .. frame.kind .. " length=" .. length
          )
          assertions.truthy(reader:close())
        end
        frame_offset = frame_offset + #encoded
      end
    end,
  },
}
