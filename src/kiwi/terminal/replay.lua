local Base64 = require("kiwi.terminal.base64")
local Json = require("kiwi.bench.json")
local Parser = require("kiwi.terminal.parser")

local Replay = {}

Replay.version = 1
Replay.max_event_bytes = 64 * 1024
Replay.max_line_bytes = 256 * 1024

local Recorder = {}
Recorder.__index = Recorder

function Recorder.new(path)
  local file, message = io.open(path, "wb")
  if not file then
    error("Unable to open recording " .. path .. ": " .. message)
  end
  return setmetatable({ file = file, path = path }, Recorder)
end

function Recorder:write(event)
  assert(self.file ~= nil, "recording is closed")
  self.file:write(Json.encode(event), "\n")
  self.file:flush()
end

function Recorder:bytes(kind, bytes)
  assert(#bytes <= Replay.max_event_bytes, "recording event exceeds 64 KiB")
  self:write({ data = Base64.encode(bytes), event = kind, v = Replay.version })
end

function Recorder:output(bytes)
  self:bytes("output", bytes)
end

function Recorder:input(bytes)
  self:bytes("input", bytes)
end

function Recorder:resize(columns, rows)
  assert(columns > 0 and rows > 0, "recording dimensions must be positive")
  self:write({ cols = columns, event = "resize", rows = rows, v = Replay.version })
end

function Recorder:close()
  if self.file then
    self.file:close()
    self.file = nil
  end
end

local function required_number(line, name)
  local value = line:match('"' .. name .. '":(%d+)')
  assert(value ~= nil, "recording event has no " .. name)
  return tonumber(value)
end

local function event_from_line(line)
  assert(#line <= Replay.max_line_bytes, "recording line exceeds 256 KiB")
  assert(line:match('"v":1') ~= nil, "unsupported recording version")
  local kind = line:match('"event":"([a-z]+)"')
  assert(kind ~= nil, "recording event has no event name")
  if kind == "resize" then
    return { event = kind, cols = required_number(line, "cols"), rows = required_number(line, "rows") }
  end
  if kind == "output" or kind == "input" then
    local data = line:match('"data":"([A-Za-z0-9+/=]*)"')
    assert(data ~= nil, "recording byte event has invalid base64 data")
    local bytes = Base64.decode(data)
    assert(#bytes <= Replay.max_event_bytes, "recording byte event exceeds 64 KiB")
    return { event = kind, bytes = bytes }
  end
  error("unsupported recording event: " .. kind)
end

function Replay.each(path, callback)
  local file, message = io.open(path, "rb")
  if not file then
    error("Unable to open replay " .. path .. ": " .. message)
  end
  local ok, result = xpcall(function()
    local line_number = 0
    for line in file:lines() do
      line_number = line_number + 1
      local parsed, event = xpcall(function()
        return event_from_line(line)
      end, debug.traceback)
      if not parsed then
        error("Invalid replay event at line " .. line_number .. ": " .. event)
      end
      callback(event)
    end
  end, debug.traceback)
  file:close()
  if not ok then
    error(result)
  end
end

function Replay.apply_file(state, path)
  local parser = Parser.new(state)
  Replay.each(path, function(event)
    if event.event == "resize" then
      state:resize(event.cols, event.rows)
    elseif event.event == "output" then
      parser:feed(event.bytes)
    end
  end)
  parser:finish()
  return parser.stats
end

Replay.Recorder = Recorder

return Replay
