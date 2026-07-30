local assertions = require("support.assertions")
local Checksum = require("recording.checksum")
local Coordinator = require("runtime.coordinator")
local Format = require("recording.format")
local Frames = require("recording.frames")
local Replay = require("backend.replay")
local Terminal = require("terminal.terminal")
local Event = require("runtime.event")

local function source(bytes)
  local value = { bytes = bytes, offset = 1 }
  function value:read(count)
    if self.offset > #self.bytes then
      return nil
    end
    local finish = math.min(#self.bytes, self.offset + count - 1)
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

return {
  {
    name = "coordinator frame stepping applies replay events outside the backend",
    run = function()
      local frame = assert(Frames.from_event(assert(Event.output("abc", 4))))
      local terminal = assert(Terminal.new({ columns = 4, rows = 1 }))
      local replay = assert(Replay.new(source(recording({ frame }))))
      local coordinator = assert(Coordinator.new(terminal, replay))
      local step = assert(coordinator:step_frame())
      assertions.equal(1, step.frame_index)
      assertions.equal("a", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal("b", terminal.primary_screen.rows[1].cells[2].text)
      assertions.equal("c", terminal.primary_screen.rows[1].cells[3].text)
      assertions.equal(4, coordinator:status().terminal_time_us)
      assertions.equal(1, coordinator:status().event_sequence)
      assertions.truthy(coordinator:stop())
    end,
  },
  {
    name = "coordinator steps output through one parsed control sequence at a time",
    run = function()
      local frame = assert(Frames.from_event(assert(Event.output("text\27[31mX\7", 0))))
      local terminal = assert(Terminal.new({ columns = 8, rows = 1 }))
      local replay = assert(Replay.new(source(recording({ frame }))))
      local coordinator = assert(Coordinator.new(terminal, replay))
      local step = assert(coordinator:step_control_sequence())
      assertions.equal("control_sequence", step.kind)
      assertions.equal("csi", step.boundary.kind)
      assertions.equal(9, step.bytes)
      assertions.equal("t", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal(1, terminal.rendition.foreground.index)
      step = assert(coordinator:step_control_sequence())
      assertions.equal("control_sequence", step.kind)
      assertions.equal("control", step.boundary.kind)
      assertions.equal(2, step.bytes)
      assertions.equal("X", terminal.primary_screen.rows[1].cells[5].text)
      assertions.equal("bell", step.semantic_events[#step.semantic_events].kind)
      assertions.falsy(coordinator:step_control_sequence())
      assertions.equal("exhausted", replay:status().state)
      assertions.truthy(coordinator:stop())
    end,
  },
  {
    name = "coordinator preserves frame order during regular replay updates",
    run = function()
      local terminal = assert(Terminal.new({ columns = 4, rows = 1 }))
      local replay = assert(Replay.new(source(recording({
        assert(Frames.from_event(assert(Event.output("a", 2)))),
        assert(Frames.from_event(assert(Event.output("b", 3)))),
      }))))
      local coordinator = assert(Coordinator.new(terminal, replay))
      assertions.equal(0, #assert(coordinator:update(1)))
      local applied = assert(coordinator:update(4))
      assertions.equal(2, #applied)
      assertions.equal("a", terminal.primary_screen.rows[1].cells[1].text)
      assertions.equal("b", terminal.primary_screen.rows[1].cells[2].text)
      assertions.equal(5, coordinator:status().terminal_time_us)
      assertions.truthy(coordinator:stop())
    end,
  },
}
