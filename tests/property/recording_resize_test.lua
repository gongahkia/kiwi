local assertions = require("support.assertions")
local Checksum = require("recording.checksum")
local Coordinator = require("runtime.coordinator")
local Event = require("runtime.event")
local Format = require("recording.format")
local Frames = require("recording.frames")
local Replay = require("backend.replay")
local Terminal = require("terminal.terminal")

local fragments = {
  "A",
  "B",
  "\n",
  "\r",
  "\t",
  "\195",
  "\169",
  "\27[2J",
  "\27[2;3H",
  "\27[31m",
  "\27[0m",
  "\27[?1049h",
  "\27[?1049l",
}

local function source(bytes, chunk_size)
  local value = { bytes = bytes, offset = 1 }
  function value:read(count)
    if self.offset > #self.bytes then
      return nil
    end
    local finish = math.min(#self.bytes, self.offset + math.min(count, chunk_size) - 1)
    local output = self.bytes:sub(self.offset, finish)
    self.offset = finish + 1
    return output
  end
  function value:close()
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

local function hex(bytes)
  local values = {}
  for index = 1, #bytes do
    values[index] = string.format("%02X", bytes:byte(index))
  end
  return table.concat(values)
end

local function event_description(events)
  local values = {}
  for index, event in ipairs(events) do
    if event.kind == "output" then
      values[index] = "output:" .. event.delta_us .. ":" .. hex(event.data)
    else
      values[index] = "resize:" .. event.delta_us .. ":" .. event.columns .. "x" .. event.rows
    end
  end
  return table.concat(values, ",")
end

local function generated_output()
  local parts = {}
  for index = 1, math.random(1, 4) do
    parts[index] = fragments[math.random(1, #fragments)]
  end
  return table.concat(parts)
end

local function generated_events()
  local events = {
    assert(Event.output("P\27[2;2H\27[?1049hA\27[?1049l", 0)),
    assert(Event.resize(math.random(1, 6), math.random(1, 4), 0, 0, math.random(0, 4))),
  }
  for _ = 1, math.random(8, 24) do
    if math.random(1, 3) == 1 then
      events[#events + 1] =
        assert(Event.resize(math.random(1, 6), math.random(1, 4), 0, 0, math.random(0, 4)))
    else
      events[#events + 1] = assert(Event.output(generated_output(), math.random(0, 4)))
    end
  end
  return events
end

local function chunk_events(events)
  local chunked = {}
  for _, event in ipairs(events) do
    if event.kind ~= "output" or #event.data == 1 then
      chunked[#chunked + 1] = event
    else
      local offset = 1
      local first = true
      while offset <= #event.data do
        local size = math.random(1, math.min(4, #event.data - offset + 1))
        chunked[#chunked + 1] = assert(
          Event.output(event.data:sub(offset, offset + size - 1), first and event.delta_us or 0)
        )
        first = false
        offset = offset + size
      end
    end
  end
  return chunked
end

local function apply(terminal, events)
  for _, event in ipairs(events) do
    if event.kind == "output" then
      assert(terminal:feed_output(event.data))
    else
      assert(terminal:resize(event.columns, event.rows))
    end
    assert(terminal:digest())
  end
end

local function replay(config, events, chunk_size)
  local frames = {}
  local elapsed_terminal_us = 0
  for _, event in ipairs(events) do
    frames[#frames + 1] = assert(Frames.from_event(event))
    elapsed_terminal_us = elapsed_terminal_us + event.delta_us
  end
  local terminal = assert(Terminal.new(config))
  local coordinator =
    assert(Coordinator.new(terminal, assert(Replay.new(source(recording(frames), chunk_size)))))
  assert(coordinator:update(elapsed_terminal_us))
  local result = coordinator:terminal_instance()
  assert(result:digest())
  assert(coordinator:stop())
  return result
end

return {
  {
    name = "property generated recordings preserve resize semantics through random chunking",
    run = function()
      for iteration = 1, 128 do
        local config = { columns = 4, rows = 3, scrollback_limit = 4 }
        local events = generated_events()
        local chunked = chunk_events(events)
        local direct = assert(Terminal.new(config))
        local chunked_direct = assert(Terminal.new(config))
        apply(direct, events)
        apply(chunked_direct, chunked)
        local replayed = replay(config, chunked, math.random(1, 7))
        local context = "resize recording iteration "
          .. iteration
          .. " events="
          .. event_description(events)
        assertions.equal(assert(direct:digest()), assert(chunked_direct:digest()), context)
        assertions.equal(assert(direct:digest()), assert(replayed:digest()), context)
      end
    end,
  },
  {
    name = "property generated writes switches movements and resizes retain terminal invariants",
    run = function()
      for iteration = 1, 128 do
        local terminal = assert(Terminal.new({ columns = 4, rows = 3, scrollback_limit = 4 }))
        local events = generated_events()
        apply(terminal, events)
        assertions.truthy(
          assert(terminal:digest()) ~= "",
          "resize invariant iteration " .. iteration .. " events=" .. event_description(events)
        )
      end
    end,
  },
}
