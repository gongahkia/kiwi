local assertions = require("support.assertions")
local Coordinator = require("runtime.coordinator")
local Effect = require("effects.effect")
local Host = require("effects.host")
local Event = require("runtime.event")
local Frames = require("recording.frames")
local RecordingWriter = require("recording.writer")
local Replay = require("backend.replay")
local Terminal = require("terminal.terminal")

local function manifest()
  return {
    api_version = 1,
    capabilities = { "frame_update", "terminal_events" },
    determinism = "deterministic",
    id = "test.generated-subscriptions",
    parameters = {},
    version = "0.1.0",
  }
end

local function source(bytes)
  local value = { bytes = bytes, offset = 1 }
  function value:read(count)
    if self.offset > #self.bytes then
      return nil
    end
    local finish = math.min(#self.bytes, self.offset + math.min(count, 5) - 1)
    local chunk = self.bytes:sub(self.offset, finish)
    self.offset = finish + 1
    return chunk
  end
  function value:close()
    return true
  end
  return value
end

local function recording(events)
  local sink = { chunks = {} }
  function sink:write(bytes)
    self.chunks[#self.chunks + 1] = bytes
    return true
  end
  function sink:flush()
    return true
  end
  function sink:close()
    return true
  end
  local writer = assert(RecordingWriter.new(sink, { format = "stanczyk-recording" }))
  for _, event in ipairs(events) do
    assert(writer:append(assert(Frames.from_event(event))))
  end
  assert(writer:close())
  return table.concat(sink.chunks)
end

local function payload_trace(event)
  if event.kind == "input" or event.kind == "output" then
    return event.payload.bytes
  end
  if event.kind == "cursor" then
    return event.payload.row .. ":" .. event.payload.column
  end
  if event.kind == "scroll" then
    return event.payload.direction .. ":" .. event.payload.top .. ":" .. event.payload.bottom
  end
  if event.kind == "resize" then
    return event.payload.columns .. ":" .. event.payload.rows
  end
  if event.kind == "screen_switch" then
    return event.payload.screen
  end
  if event.kind == "damage" then
    return tostring(#event.payload.ranges)
  end
  return ""
end

local function run(events, advances)
  local trace = {}
  local terminal = assert(Terminal.new({ columns = 4, rows = 3, scrollback_limit = 8 }))
  local previous_sequence = 0
  local previous_timestamp = 0
  local effect = assert(Effect.new(manifest(), {
    on_event = function(_, _, event)
      assertions.equal(previous_sequence + 1, event.sequence)
      assertions.truthy(event.timestamp_us >= previous_timestamp)
      previous_sequence = event.sequence
      previous_timestamp = event.timestamp_us
      trace[#trace + 1] = table.concat({
        event.kind,
        event.sequence,
        event.timestamp_us,
        payload_trace(event),
      }, ":")
    end,
  }))
  local host = assert(Host.new({ effect }, {
    max_event_payload_bytes = 3,
    terminal = { columns = 4, rows = 3 },
    viewport = { height = 30, width = 40 },
  }))
  local coordinator =
    assert(Coordinator.new(terminal, assert(Replay.new(source(recording(events)))), {
      effect_host = host,
    }))
  for _, advance in ipairs(advances) do
    assert(coordinator:update(advance))
  end
  while coordinator:status().pending_backend_events > 0 do
    assert(coordinator:update(0))
  end
  assertions.truthy(coordinator:stop())
  return assert(terminal:digest()), table.concat(trace, "|")
end

return {
  {
    name = "property generated lifecycle subscriptions preserve replay semantics and order",
    run = function()
      local events = {}
      local direct = assert(Terminal.new({ columns = 4, rows = 3, scrollback_limit = 8 }))
      local elapsed = 0
      local output = { "A", "\7", "\n", "\27[2S", "\27[1T", "\27[?47h", "\27[?47l" }
      for _ = 1, 96 do
        local delta_us = math.random(0, 20)
        elapsed = elapsed + delta_us
        local event
        if math.random(1, 4) == 1 then
          event = assert(
            Event.resize(
              math.random(1, 8),
              math.random(1, 5),
              math.random(0, 1) == 1 and math.random(1, 160) or 0,
              math.random(0, 1) == 1 and math.random(1, 120) or 0,
              delta_us
            )
          )
          assert(direct:resize(event.columns, event.rows))
        else
          event = assert(Event.output(output[math.random(1, #output)], delta_us))
          assert(direct:feed_output(event.data))
        end
        events[#events + 1] = event
      end
      local first_digest, first_trace = run(events, { elapsed })
      local second_digest, second_trace =
        run(events, { math.floor(elapsed / 3), elapsed - math.floor(elapsed / 3) })
      assertions.equal(assert(direct:digest()), first_digest)
      assertions.equal(first_digest, second_digest)
      assertions.equal(first_trace, second_trace)
      assertions.truthy(#first_trace > 0)
    end,
  },
}
