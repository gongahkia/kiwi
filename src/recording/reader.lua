local Errors = require("runtime.errors")

local RecordingReader = {}
local reader_mt = {}
reader_mt.__index = reader_mt

RecordingReader.contract = {
  constructor = "new(source) -> reader | nil, error",
  read_next = "read_next() -> frame | nil, error?",
  metadata = "metadata() -> table | nil, error?",
  close = "close()",
}

function RecordingReader.new(source)
  if type(source) ~= "table" then
    return nil, Errors.new("config_error", "recording source must be a table")
  end
  return setmetatable({ source = source, closed = false }, reader_mt)
end

function reader_mt:read_next()
  if self.closed then
    return nil, Errors.new("recording_io_error", "recording reader is closed")
  end
  return nil, Errors.new("recording_io_error", "recording decoding is not implemented")
end

function reader_mt:metadata()
  if self.closed then
    return nil, Errors.new("recording_io_error", "recording reader is closed")
  end
  return nil, Errors.new("recording_io_error", "recording metadata is not implemented")
end

function reader_mt:close()
  self.closed = true
end

return RecordingReader
