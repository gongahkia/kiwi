local assertions = require("support.assertions")
local Coordinator = require("runtime.coordinator")
local Event = require("runtime.event")
local Frames = require("recording.frames")
local RecordingWriter = require("recording.writer")
local Replay = require("backend.replay")
local Terminal = require("terminal.terminal")

local function sink()
  local value = { chunks = {} }
  function value:write(bytes)
    self.chunks[#self.chunks + 1] = bytes
    return true
  end
  function value:flush()
    return true
  end
  function value:close()
    return true
  end
  return value
end

local function source(bytes)
  local value = { bytes = bytes, offset = 1, seek_calls = 0 }
  function value:read(count)
    if self.offset > #self.bytes then
      return nil
    end
    local finish = math.min(#self.bytes, self.offset + math.min(count, 3) - 1)
    local output = self.bytes:sub(self.offset, finish)
    self.offset = finish + 1
    return output
  end
  function value:close()
    return true
  end
  function value:seek(offset)
    if offset < 0 or offset > #self.bytes then
      return nil, "invalid offset"
    end
    self.offset = offset + 1
    self.seek_calls = self.seek_calls + 1
    return offset
  end
  return value
end

local function apply_directly(terminal, events)
  for _, event in ipairs(events) do
    if event.kind == "output" then
      assert(terminal:feed_output(event.data))
    elseif event.kind == "resize" then
      assert(terminal:resize(event.columns, event.rows))
    end
  end
end

return {
  {
    name = "saved representative recording reopens pauses steps and seeks",
    run = function()
      local config = { columns = 3, rows = 1, scrollback_limit = 2 }
      local events = {
        assert(Event.output("ABC", 2)),
        assert(Event.resize(2, 2, 0, 0, 2)),
        assert(Event.output("\rD", 3)),
      }
      local checkpoint_terminal = assert(Terminal.new(config))
      assert(checkpoint_terminal:feed_output(events[1].data))
      local target = sink()
      local writer = assert(RecordingWriter.new(target, { format = "stanczyk-recording" }))
      assert(writer:append(assert(Frames.from_event(events[1]))))
      assert(writer:append_checkpoint(checkpoint_terminal, 1))
      assert(writer:append(assert(Frames.from_event(events[2]))))
      assert(writer:append(assert(Frames.from_event(events[3]))))
      assert(writer:close())

      local reopened_source = source(table.concat(target.chunks))
      local replay = assert(Replay.new(reopened_source))
      local terminal = assert(Terminal.new(config))
      local coordinator = assert(Coordinator.new(terminal, replay))
      assertions.equal(1, #assert(coordinator:update(2)))
      assertions.truthy(replay:pause())
      assertions.equal(0, #assert(coordinator:update(100)))
      local checkpoint_step = assert(coordinator:step_frame())
      assertions.equal(2, checkpoint_step.frame_index)
      assertions.falsy(checkpoint_step.applied)
      assertions.truthy(replay:resume())
      assertions.equal(2, #assert(coordinator:update(5)))

      local direct = assert(Terminal.new(config))
      apply_directly(direct, events)
      assertions.equal(assert(direct:digest()), assert(terminal:digest()))
      assertions.equal(1, replay:status().checkpoint_status.indexed)
      assertions.truthy(reopened_source.seek_calls > 0)
      assert(coordinator:seek(8))
      assertions.equal(assert(direct:digest()), assert(coordinator:terminal_instance():digest()))
      assertions.truthy(coordinator:stop())
    end,
  },
}
