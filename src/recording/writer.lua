local Checksum = require("recording.checksum")
local Errors = require("runtime.errors")
local Format = require("recording.format")
local Frames = require("recording.frames")
local Metadata = require("recording.metadata")

local RecordingWriter = {}
local writer_mt = {}
writer_mt.__index = writer_mt

RecordingWriter.contract = {
  constructor = "new(sink, metadata) -> writer | nil, error",
  append = "append(frame) -> true | nil, error",
  append_checkpoint = "append_checkpoint(terminal, delta_us?, limits?) -> true | nil, error",
  close = "close() -> true | nil, error",
}

local function io_error(operation, detail)
  return Errors.new("recording_io_error", "recording sink " .. operation .. " failed", detail)
end

local function validate_sink(sink)
  if type(sink) ~= "table" then
    return nil, Errors.new("config_error", "recording sink must be a table")
  end
  for _, method in ipairs({ "write", "flush", "close" }) do
    if type(sink[method]) ~= "function" then
      return nil, Errors.new("config_error", "recording sink must implement " .. method)
    end
  end
  return sink
end

local function call_sink(sink, operation, bytes)
  local ok, result, detail
  if bytes == nil then
    ok, result, detail = pcall(sink[operation], sink)
  else
    ok, result, detail = pcall(sink[operation], sink, bytes)
  end
  if not ok then
    return nil, io_error(operation, { cause = result })
  end
  if not result then
    return nil, io_error(operation, { cause = detail })
  end
  if operation == "write" and type(result) == "number" and result ~= #bytes then
    return nil, io_error(operation, { expected = #bytes, written = result })
  end
  return true
end

local function close_sink(sink)
  local closed, close_error = call_sink(sink, "close")
  if not closed then
    return nil, close_error
  end
  return true
end

local function frame_bytes(frame)
  local checksum_bytes, checksum_bytes_error = Format.frame_checksum_bytes(frame)
  if not checksum_bytes then
    return nil, checksum_bytes_error
  end
  local checksum, checksum_error = Checksum.crc32(checksum_bytes)
  if not checksum then
    return nil, checksum_error
  end
  if frame.checksum ~= checksum then
    return nil, Errors.new("config_error", "recording frame checksum does not match payload")
  end
  return Format.encode_frame(frame)
end

local function unavailable(writer)
  if writer.closed then
    return nil, Errors.new("recording_io_error", "recording writer is closed")
  end
  if writer.failure then
    return nil, writer.failure
  end
  return true
end

function RecordingWriter.new(sink, metadata)
  local valid_sink, sink_error = validate_sink(sink)
  if not valid_sink then
    return nil, sink_error
  end
  local metadata_bytes, metadata_error = Metadata.encode(metadata)
  if not metadata_bytes then
    return nil, metadata_error
  end
  if #metadata_bytes > Format.default_max_metadata_bytes then
    return nil,
      Errors.new("config_error", "recording metadata exceeds default format bound", {
        limit = Format.default_max_metadata_bytes,
        provided = #metadata_bytes,
      })
  end
  local metadata_checksum, checksum_error = Checksum.crc32(metadata_bytes)
  if not metadata_checksum then
    return nil, checksum_error
  end
  local preamble, preamble_error = Format.encode_preamble({
    flags = 0,
    major_version = Format.current_major_version,
    metadata_checksum = metadata_checksum,
    metadata_length = #metadata_bytes,
    minor_version = Format.current_minor_version,
  })
  if not preamble then
    return nil, preamble_error
  end
  local writer = setmetatable({
    closed = false,
    failure = nil,
    frame_count = 0,
    metadata_bytes = metadata_bytes,
    sink = valid_sink,
  }, writer_mt)
  local written, write_error = call_sink(valid_sink, "write", preamble .. metadata_bytes)
  if not written then
    writer.failure = write_error
    close_sink(valid_sink)
    writer.closed = true
    return nil, write_error
  end
  return writer
end

function writer_mt:append(frame)
  local available, available_error = unavailable(self)
  if not available then
    return nil, available_error
  end
  local bytes, encode_error = frame_bytes(frame)
  if not bytes then
    return nil, encode_error
  end
  local written, write_error = call_sink(self.sink, "write", bytes)
  if not written then
    self.failure = write_error
    return nil, write_error
  end
  self.frame_count = self.frame_count + 1
  return true
end

function writer_mt:append_checkpoint(terminal, delta_us, limits)
  local frame, frame_error = Frames.checkpoint(terminal, delta_us, limits)
  if not frame then
    return nil, frame_error
  end
  return self:append(frame)
end

function writer_mt:close()
  if self.closed then
    if self.failure then
      return nil, self.failure
    end
    return true
  end
  local flush_ok, flush_error = call_sink(self.sink, "flush")
  local close_ok, close_error = close_sink(self.sink)
  self.closed = true
  if not flush_ok then
    self.failure = flush_error
    return nil, flush_error
  end
  if not close_ok then
    self.failure = close_error
    return nil, close_error
  end
  return true
end

return RecordingWriter
