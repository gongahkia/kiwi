local assertions = require("support.assertions")
local Checksum = require("recording.checksum")
local Coordinator = require("runtime.coordinator")
local Format = require("recording.format")
local Frames = require("recording.frames")
local Replay = require("backend.replay")
local Terminal = require("terminal.terminal")
local Event = require("runtime.event")

local function source(bytes, seekable)
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
  if seekable then
    function value:seek(offset)
      if offset < 0 or offset > #self.bytes then
        return nil, "invalid offset"
      end
      self.offset = offset + 1
      return offset
    end
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

local function apply_directly(terminal, events)
  for _, event in ipairs(events) do
    local normalised = assert(Event.validate(event))
    if normalised.kind == "output" then
      assert(terminal:feed_output(normalised.data))
    elseif normalised.kind == "resize" then
      assert(terminal:resize(normalised.columns, normalised.rows))
    end
  end
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
  {
    name = "coordinator bounds updates and drains ordered backend backlog",
    run = function()
      local terminal = assert(Terminal.new({ columns = 4, rows = 1 }))
      local replay = assert(Replay.new(source(recording({
        assert(Frames.from_event(assert(Event.output("a", 0)))),
        assert(Frames.from_event(assert(Event.output("b", 0)))),
        assert(Frames.from_event(assert(Event.output("c", 0)))),
      }))))
      local coordinator =
        assert(Coordinator.new(terminal, replay, { max_backend_events_per_update = 1 }))
      local applied = assert(coordinator:update(0))
      assertions.equal(1, #applied)
      assertions.equal(2, coordinator:status().pending_backend_events)
      applied = assert(coordinator:update(0))
      assertions.equal("b", terminal.primary_screen.rows[1].cells[2].text)
      assertions.equal(1, coordinator:status().pending_backend_events)
      applied = assert(coordinator:update(0))
      assertions.equal("c", terminal.primary_screen.rows[1].cells[3].text)
      assertions.equal(0, coordinator:status().pending_backend_events)
      local value, error_value =
        Coordinator.new(terminal, replay, { max_backend_events_per_update = 0 })
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      assertions.truthy(coordinator:stop())
    end,
  },
  {
    name = "replay matches direct application for a representative event stream",
    run = function()
      local events = {
        assert(Event.output("one\n\27[31mred", 3)),
        assert(Event.input("typed", 2)),
        assert(Event.mark("phase", { number = 1 }, 1)),
        assert(Event.clock_advance(4)),
        assert(Event.output("\27[0m\n\195", 5)),
        assert(Event.output("\169 \27[?1049halt\27[?1049l", 0)),
      }
      local direct = assert(Terminal.new({ columns = 8, rows = 3, scrollback_limit = 4 }))
      apply_directly(direct, events)

      local frames = {}
      for _, event in ipairs(events) do
        frames[#frames + 1] = assert(Frames.from_event(event))
      end
      local replayed = assert(Terminal.new({ columns = 8, rows = 3, scrollback_limit = 4 }))
      local coordinator =
        assert(Coordinator.new(replayed, assert(Replay.new(source(recording(frames))))))
      local applied = assert(coordinator:update(15))
      assertions.equal(#events, #applied)
      assertions.equal(15, coordinator:status().terminal_time_us)
      assertions.equal(assert(direct:digest()), assert(replayed:digest()))
      assertions.truthy(coordinator:stop())
    end,
  },
  {
    name = "replay applies resize events deterministically",
    run = function()
      local config = { columns = 3, rows = 1, scrollback_limit = 2 }
      local events = {
        assert(Event.output("ABC", 2)),
        assert(Event.resize(2, 2, 0, 0, 3)),
        assert(Event.output("\rD", 4)),
        assert(Event.resize(4, 1, 0, 0, 1)),
        assert(Event.output("E", 0)),
      }
      local direct = assert(Terminal.new(config))
      apply_directly(direct, events)
      local frames = {}
      for _, event in ipairs(events) do
        frames[#frames + 1] = assert(Frames.from_event(event))
      end
      local replayed = assert(Terminal.new(config))
      local coordinator =
        assert(Coordinator.new(replayed, assert(Replay.new(source(recording(frames))))))
      assertions.equal(#events, #assert(coordinator:update(10)))
      assertions.equal(assert(direct:digest()), assert(replayed:digest()))
      assertions.equal(4, replayed.config.columns)
      assertions.equal(1, replayed.config.rows)
      assertions.truthy(coordinator:stop())
    end,
  },
  {
    name = "coordinator restores an indexed checkpoint and replays its suffix",
    run = function()
      local checkpoint_terminal = assert(Terminal.new({ columns = 4, rows = 1 }))
      assert(checkpoint_terminal:feed_output("A"))
      local checkpoint = assert(Frames.checkpoint(checkpoint_terminal, 0))
      local initial = assert(Terminal.new({ columns = 4, rows = 1 }))
      local replay = assert(Replay.new(source(
        recording({
          assert(Frames.from_event(assert(Event.output("A", 2)))),
          checkpoint,
          assert(Frames.from_event(assert(Event.output("B", 3)))),
        }),
        true
      )))
      local coordinator = assert(Coordinator.new(initial, replay))
      local applied = assert(coordinator:seek(5))
      assertions.equal(1, #applied)
      local restored = coordinator:terminal_instance()
      assertions.equal("A", restored.primary_screen.rows[1].cells[1].text)
      assertions.equal("B", restored.primary_screen.rows[1].cells[2].text)
      assertions.equal(5, coordinator:status().terminal_time_us)
      assertions.truthy(coordinator:stop())
    end,
  },
  {
    name = "indexed checkpoint restoration matches replay from the beginning",
    run = function()
      local config = { columns = 8, rows = 3, scrollback_limit = 4 }
      local checkpoint_terminal = assert(Terminal.new(config))
      local prefix = {
        assert(Event.output("one\n\27[32mgreen", 2)),
        assert(Event.output("\27[0m\27[?1049halt\27[?1049l", 3)),
      }
      apply_directly(checkpoint_terminal, prefix)
      local suffix = {
        assert(Event.output("\27[31mred\27[0m\n\195", 5)),
        assert(Event.mark("suffix", { complete = true }, 2)),
        assert(Event.clock_advance(1)),
        assert(Event.output("\169", 0)),
      }
      local frames = {
        assert(Frames.from_event(prefix[1])),
        assert(Frames.from_event(prefix[2])),
        assert(Frames.checkpoint(checkpoint_terminal, 1)),
      }
      for _, event in ipairs(suffix) do
        frames[#frames + 1] = assert(Frames.from_event(event))
      end
      local bytes = recording(frames)

      local replayed = assert(Terminal.new(config))
      local full = assert(Coordinator.new(replayed, assert(Replay.new(source(bytes, true)))))
      assert(full:update(14))

      local restored = assert(Terminal.new(config))
      local sought = assert(Coordinator.new(restored, assert(Replay.new(source(bytes, true)))))
      assert(sought:seek(14))
      assertions.equal(assert(replayed:digest()), assert(sought:terminal_instance():digest()))
      assertions.equal(14, sought:status().terminal_time_us)
      assertions.truthy(full:stop())
      assertions.truthy(sought:stop())
    end,
  },
  {
    name = "checkpoint seeks across resizes match uninterrupted replay",
    run = function()
      local config = { columns = 3, rows = 1, scrollback_limit = 2 }
      local before_resize = assert(Terminal.new(config))
      assert(before_resize:feed_output("ABC"))
      local after_resize = assert(Terminal.new(config))
      assert(after_resize:feed_output("ABC"))
      assert(after_resize:resize(2, 2))
      assert(after_resize:feed_output("\rD"))
      local pre_resize_checkpoint = {
        assert(Frames.from_event(assert(Event.output("ABC", 2)))),
        assert(Frames.checkpoint(before_resize, 1)),
        assert(Frames.from_event(assert(Event.resize(2, 2, 0, 0, 2)))),
        assert(Frames.from_event(assert(Event.output("\rD", 3)))),
        assert(Frames.from_event(assert(Event.output("E", 2)))),
      }
      local post_resize_checkpoint = {
        assert(Frames.from_event(assert(Event.output("ABC", 2)))),
        assert(Frames.from_event(assert(Event.resize(2, 2, 0, 0, 2)))),
        assert(Frames.from_event(assert(Event.output("\rD", 3)))),
        assert(Frames.checkpoint(after_resize, 1)),
        assert(Frames.from_event(assert(Event.output("E", 2)))),
      }
      for _, frames in ipairs({ pre_resize_checkpoint, post_resize_checkpoint }) do
        local bytes = recording(frames)
        local uninterrupted_terminal = assert(Terminal.new(config))
        local uninterrupted =
          assert(Coordinator.new(uninterrupted_terminal, assert(Replay.new(source(bytes, true)))))
        assert(uninterrupted:update(10))
        local restored_terminal = assert(Terminal.new(config))
        local restored =
          assert(Coordinator.new(restored_terminal, assert(Replay.new(source(bytes, true)))))
        assert(restored:seek(10))
        assertions.equal(
          assert(uninterrupted_terminal:digest()),
          assert(restored:terminal_instance():digest())
        )
        assertions.truthy(uninterrupted:stop())
        assertions.truthy(restored:stop())
      end
    end,
  },
}
