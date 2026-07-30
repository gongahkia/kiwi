local Errors = require("runtime.errors")
local Format = require("recording.format")
local Metadata = require("recording.metadata")

local RecordingReader = {}
local reader_mt = {}
reader_mt.__index = reader_mt

RecordingReader.contract = {
  constructor = "new(source, limits?) -> reader | nil, error",
  read_next = "read_next() -> frame | nil, error?",
  metadata = "metadata() -> table | nil, error?",
  version = "version() -> version | nil, error?",
  close = "close() -> true | nil, error",
  position = "position() -> byte_offset | nil, error",
  seek_frame = "seek_frame(byte_offset) -> true | nil, error",
}

local function io_error(operation, detail)
  return Errors.new("recording_io_error", "recording source " .. operation .. " failed", detail)
end

local function corrupt(message, detail)
  return Errors.new("recording_corrupt", message, detail)
end

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function validate_source(source)
  if type(source) ~= "table" then
    return nil, Errors.new("config_error", "recording source must be a table")
  end
  for _, method in ipairs({ "read", "close" }) do
    if type(source[method]) ~= "function" then
      return nil, Errors.new("config_error", "recording source must implement " .. method)
    end
  end
  return source
end

local function read_exact(reader, length, name, allow_eof)
  if length == 0 then
    return ""
  end
  local chunks = {}
  local received = 0
  while received < length do
    local ok, value, detail = pcall(reader.source.read, reader.source, length - received)
    if not ok then
      return nil, io_error("read", { cause = value, requested = length - received })
    end
    if value == nil then
      if detail ~= nil then
        return nil, io_error("read", { cause = detail, requested = length - received })
      end
      if received == 0 and allow_eof then
        return nil, nil, true
      end
      return nil,
        corrupt("truncated recording " .. name, { expected = length, received = received })
    end
    if type(value) ~= "string" then
      return nil, io_error("read", { provided = type(value), requested = length - received })
    end
    if #value == 0 then
      return nil,
        io_error("read", { message = "source returned empty bytes", requested = length - received })
    end
    if #value > length - received then
      return nil, io_error("read", { received = #value, requested = length - received })
    end
    chunks[#chunks + 1] = value
    received = received + #value
    reader.byte_offset = reader.byte_offset + #value
  end
  return table.concat(chunks)
end

local function fail(reader, error_value)
  reader.failure = error_value
  return nil, error_value
end

local function initialize(reader)
  if reader.failure then
    return nil, reader.failure
  end
  if reader.initialized then
    return true
  end
  local preamble_bytes, preamble_error = read_exact(reader, Format.preamble_size, "preamble")
  if not preamble_bytes then
    return fail(reader, preamble_error)
  end
  local preamble, decode_error = Format.decode_preamble(preamble_bytes)
  if not preamble then
    return fail(reader, decode_error)
  end
  local version, version_error = Format.negotiate_version(preamble)
  if not version then
    return fail(reader, version_error)
  end
  local valid, validation_error = Format.validate_preamble(preamble, reader.limits)
  if not valid then
    return fail(reader, validation_error)
  end
  local metadata_bytes, metadata_read_error =
    read_exact(reader, preamble.metadata_length, "metadata")
  if not metadata_bytes then
    return fail(reader, metadata_read_error)
  end
  local checked_metadata, metadata_error =
    Format.decode_metadata(metadata_bytes, 1, preamble, reader.limits)
  if not checked_metadata then
    return fail(reader, metadata_error)
  end
  local metadata, decode_metadata_error = Metadata.decode(checked_metadata)
  if not metadata then
    return fail(reader, decode_metadata_error)
  end
  reader.initialized = true
  reader.metadata_value = metadata
  reader.preamble = preamble
  reader.version_info = version
  reader.frame_start_offset = reader.byte_offset
  return true
end

function RecordingReader.new(source, limits)
  local valid_source, source_error = validate_source(source)
  if not valid_source then
    return nil, source_error
  end
  local normalised_limits, limits_error = Format.normalise_limits(limits)
  if not normalised_limits then
    return nil, limits_error
  end
  return setmetatable({
    closed = false,
    byte_offset = 0,
    ended = false,
    failure = nil,
    initialized = false,
    limits = normalised_limits,
    source = valid_source,
  }, reader_mt)
end

function reader_mt:read_next()
  if self.closed then
    return nil, Errors.new("recording_io_error", "recording reader is closed")
  end
  local initialized, initialize_error = initialize(self)
  if not initialized then
    return nil, initialize_error
  end
  if self.ended then
    return nil
  end
  local header_bytes, header_error, eof =
    read_exact(self, Format.frame_header_size, "frame header", true)
  if eof then
    self.ended = true
    return nil
  end
  if not header_bytes then
    return fail(self, header_error)
  end
  local header, decode_error = Format.decode_frame_header(header_bytes)
  if not header then
    return fail(self, decode_error)
  end
  local valid, validation_error = Format.validate_frame_header(header, self.limits)
  if not valid then
    return fail(self, validation_error)
  end
  local remainder, read_error =
    read_exact(self, header.payload_length + Format.frame_checksum_size, "frame")
  if not remainder then
    return fail(self, read_error)
  end
  local frame, frame_error = Format.decode_frame(header_bytes .. remainder, 1, self.limits)
  if not frame then
    return fail(self, frame_error)
  end
  return frame
end

function reader_mt:metadata()
  if self.closed then
    return nil, Errors.new("recording_io_error", "recording reader is closed")
  end
  local initialized, initialize_error = initialize(self)
  if not initialized then
    return nil, initialize_error
  end
  return self.metadata_value
end

function reader_mt:version()
  if self.closed then
    return nil, Errors.new("recording_io_error", "recording reader is closed")
  end
  local initialized, initialize_error = initialize(self)
  if not initialized then
    return nil, initialize_error
  end
  return {
    major_version = self.version_info.major_version,
    reader_minor_version = self.version_info.reader_minor_version,
    recording_minor_version = self.version_info.recording_minor_version,
  }
end

function reader_mt:position()
  if self.closed then
    return nil, Errors.new("recording_io_error", "recording reader is closed")
  end
  local initialized, initialize_error = initialize(self)
  if not initialized then
    return nil, initialize_error
  end
  return self.byte_offset
end

function reader_mt:seek_frame(byte_offset)
  if self.closed then
    return nil, Errors.new("recording_io_error", "recording reader is closed")
  end
  if type(byte_offset) ~= "number" or byte_offset % 1 ~= 0 or byte_offset < 0 then
    return config_error("recording seek offset must be a non-negative integer", {
      provided = byte_offset,
    })
  end
  local initialized, initialize_error = initialize(self)
  if not initialized then
    return nil, initialize_error
  end
  if byte_offset < self.frame_start_offset then
    return config_error("recording seek offset precedes the first frame", {
      first_frame_offset = self.frame_start_offset,
      provided = byte_offset,
    })
  end
  if type(self.source.seek) ~= "function" then
    return nil, Errors.new("recording_io_error", "recording source does not support seek")
  end
  local ok, result, detail = pcall(self.source.seek, self.source, byte_offset)
  if not ok then
    return nil, io_error("seek", { cause = result, offset = byte_offset })
  end
  if not result then
    return nil, io_error("seek", { cause = detail, offset = byte_offset })
  end
  if type(result) == "number" and result ~= byte_offset then
    return nil, io_error("seek", { actual = result, offset = byte_offset })
  end
  self.byte_offset = byte_offset
  self.ended = false
  return true
end

function reader_mt:close()
  if self.closed then
    if self.close_failure then
      return nil, self.close_failure
    end
    return true
  end
  self.closed = true
  local ok, result, detail = pcall(self.source.close, self.source)
  if not ok then
    self.close_failure = io_error("close", { cause = result })
    return nil, self.close_failure
  end
  if not result then
    self.close_failure = io_error("close", { cause = detail })
    return nil, self.close_failure
  end
  return true
end

return RecordingReader
