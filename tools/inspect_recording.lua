package.path = table.concat({
  "./src/?.lua",
  "./src/?/init.lua",
  package.path,
}, ";")

local Inspect = require("recording.inspect")
local Metadata = require("recording.metadata")
local RecordingReader = require("recording.reader")

local function report_error(error_value)
  io.stderr:write(error_value.kind .. ": " .. error_value.message .. "\n")
end

local path = arg[1]
if type(path) ~= "string" or path == "" or arg[2] ~= nil then
  io.stderr:write("usage: luajit tools/inspect_recording.lua recording.strec\n")
  os.exit(2)
end

local handle, open_error = io.open(path, "rb")
if not handle then
  io.stderr:write("recording_io_error: unable to open recording: " .. tostring(open_error) .. "\n")
  os.exit(1)
end

local source = {
  close = function()
    return handle:close()
  end,
  read = function(_, count)
    return handle:read(count)
  end,
}
local reader, reader_error = RecordingReader.new(source)
if not reader then
  report_error(reader_error)
  handle:close()
  os.exit(1)
end

local function fail(error_value)
  report_error(error_value)
  reader:close()
  os.exit(1)
end

local version, version_error = reader:version()
if not version then
  fail(version_error)
end
local metadata, metadata_error = reader:metadata()
if not metadata then
  fail(metadata_error)
end
local metadata_bytes, encode_error = Metadata.encode(metadata)
if not metadata_bytes then
  fail(encode_error)
end

io.write(
  string.format(
    "recording version=%d.%d reader_minor=%d\n",
    version.major_version,
    version.recording_minor_version,
    version.reader_minor_version
  )
)
io.write("metadata " .. metadata_bytes .. "\n")

local index = 0
local elapsed_us = "0"
while true do
  local frame, frame_error = reader:read_next()
  if not frame then
    if frame_error then
      fail(frame_error)
    end
    break
  end
  index = index + 1
  local line, next_elapsed = Inspect.frame_line(index, elapsed_us, frame)
  if not line then
    fail(next_elapsed)
  end
  elapsed_us = next_elapsed
  io.write(line .. "\n")
end

local closed, close_error = reader:close()
if not closed then
  report_error(close_error)
  os.exit(1)
end
io.write("summary frames=" .. index .. " duration_us=" .. elapsed_us .. "\n")
