local Base64 = require("kiwi.terminal.base64")
local Json = require("kiwi.bench.json")
local Parser = require("kiwi.terminal.parser")
local Snapshot = require("kiwi.terminal.snapshot")
local State = require("kiwi.terminal.state")

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

local function feed(parser, bytes, chunking, seed)
  if chunking == nil or chunking == "whole" then
    parser:feed(bytes)
    return seed
  end
  local offset = 1
  while offset <= #bytes do
    local count
    if chunking == "one-byte" then
      count = 1
    else
      seed = (seed * 17 + 11) % 97
      count = seed % 7 + 1
    end
    parser:feed(bytes:sub(offset, offset + count - 1))
    offset = offset + count
  end
  return seed
end

function Replay.apply_file(state, path, options)
  options = options or {}
  local chunking = options.chunking or "whole"
  assert(chunking == "whole" or chunking == "one-byte" or chunking == "random", "replay chunking is invalid")
  local seed = options.seed or 1
  assert(type(seed) == "number" and seed % 1 == 0, "replay seed must be an integer")
  local parser = Parser.new(state)
  Replay.each(path, function(event)
    if event.event == "resize" then
      state:resize(event.cols, event.rows)
    elseif event.event == "output" then
      seed = feed(parser, event.bytes, chunking, seed)
    end
  end)
  parser:finish()
  return parser.stats
end

local function signature(state, stats)
  return Snapshot.encode(state) .. "\n" .. Json.encode({
    parser = stats,
    responses = state:pop_responses(),
    unknown = state.stats.unknown,
  })
end

local function replay_variant(path, chunking, seed)
  local state = State.new(80, 24)
  local stats = Replay.apply_file(state, path, { chunking = chunking, seed = seed })
  return { signature = signature(state, stats), state = state, stats = stats }
end

function Replay.verify_chunk_invariance(path, randomized_seeds)
  randomized_seeds = randomized_seeds or 8
  assert(type(randomized_seeds) == "number" and randomized_seeds >= 1 and randomized_seeds <= 32
    and randomized_seeds % 1 == 0, "replay randomized seed count must be 1 through 32")
  local baseline = replay_variant(path, "whole", 1)
  local one_byte = replay_variant(path, "one-byte", 1)
  assert(one_byte.signature == baseline.signature, "replay is not invariant under one-byte output chunks")
  for seed = 1, randomized_seeds do
    local randomized = replay_variant(path, "random", seed)
    assert(randomized.signature == baseline.signature, "replay is not invariant under randomized output chunks (seed " .. seed .. ")")
  end
  return baseline.state, baseline.stats, randomized_seeds
end

Replay.Recorder = Recorder

return Replay
