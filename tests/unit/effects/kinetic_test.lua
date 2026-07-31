local assertions = require("support.assertions")
local Coordinator = require("runtime.coordinator")
local Effect = require("effects.effect")
local Event = require("runtime.event")
local FontFixture = require("fixtures.renderer.font")
local Frames = require("recording.frames")
local Host = require("effects.host")
local Kinetic = require("effects.kinetic")
local RecordingWriter = require("recording.writer")
local Renderer = require("renderer.renderer")
local Replay = require("backend.replay")
local Terminal = require("terminal.terminal")

local function visual_cell()
  return {
    attributes = 0,
    background = "default",
    column = 1,
    cursor = false,
    damage = true,
    foreground = "default",
    row = 1,
    screen = "primary",
    text = "A",
    width = 1,
  }
end

local function host(effects)
  return assert(Host.new(effects, {
    terminal = { columns = 2, rows = 1 },
    viewport = { height = 17, width = 18 },
  }))
end

local function begin(value)
  return assert(value:begin_visual_frame({
    terminal = { columns = 2, rows = 1 },
    viewport = { height = 17, width = 18 },
  }))
end

local function source(bytes)
  local value = { bytes = bytes, offset = 1 }
  function value:read(count)
    if self.offset > #self.bytes then
      return nil
    end
    local finish = math.min(#self.bytes, self.offset + count - 1)
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

local function graphics()
  local value = { calls = {} }
  local function record(name, ...)
    value.calls[#value.calls + 1] = { name = name, ... }
  end
  function value.newFont(path_or_size, size)
    record("newFont", path_or_size, size)
    return FontFixture.new()
  end
  function value.setColor(red, green, blue, alpha)
    record("setColor", red, green, blue, alpha)
  end
  function value.setFont(font)
    record("setFont", font)
  end
  function value.rectangle(mode, x, y, width, height)
    record("rectangle", mode, x, y, width, height)
  end
  function value.print(text, x, y)
    record("print", text, x, y)
  end
  function value.line(x1, y1, x2, y2)
    record("line", x1, y1, x2, y2)
  end
  return value
end

local function failing_transform()
  return assert(Effect.new({
    api_version = 1,
    capabilities = { "cell_transform" },
    determinism = "deterministic",
    id = "test.kinetic-failure",
    parameters = {},
    version = "0.1.0",
  }, {
    transform_cell = function()
      return { offset_x = 2, offset_y = 0 }
    end,
  }))
end

return {
  {
    name = "kinetic declares bounded deterministic transform capabilities and parameters",
    run = function()
      local effect = assert(Kinetic.new())
      local manifest = effect:manifest()
      assertions.equal(Kinetic.id, manifest.id)
      assertions.equal("cell_transform", manifest.capabilities[3])
      assertions.equal("visual_state", manifest.capabilities[4])
      assertions.equal(0, manifest.parameters.intensity.min)
      assertions.equal(1, manifest.parameters.intensity.max)
      assertions.equal(0.01, manifest.parameters.max_offset.min)
      assertions.equal(0.5, manifest.parameters.max_offset.max)
      local invalid, invalid_error = Kinetic.new({ max_offset = 0.6 })
      assertions.falsy(invalid)
      assertions.equal("effect_load_error", invalid_error.kind)
      local visual_only = assert(Effect.new({
        api_version = 1,
        capabilities = { "visual_state" },
        determinism = "deterministic",
        id = "test.visual-state-only",
        parameters = {},
        version = "0.1.0",
      }, {
        needs_redraw = function()
          return false
        end,
      }))
      invalid, invalid_error = Host.new({ visual_only })
      assertions.falsy(invalid)
      assertions.equal("effect_load_error", invalid_error.kind)
      assert(effect:set_parameters({ intensity = 0.75, reduced_motion = true }))
      invalid, invalid_error = effect:set_parameters({ decay = 0 })
      assertions.falsy(invalid)
      assertions.equal("effect_load_error", invalid_error.kind)
      assertions.equal(0.75, effect:parameters().intensity)
    end,
  },
  {
    name = "kinetic transforms reset and decay to an exact baseline deterministically",
    run = function()
      local function trace()
        local value = host({ assert(Kinetic.new({ decay = 1 })) })
        assert(value:advance(0))
        assert(value:emit("output", { bytes = "A" }, 0))
        local frame = begin(value)
        assertions.equal(true, frame.redraw)
        local active = assert(value:transform_cell(visual_cell(), true))
        assert(value:end_visual_frame())
        assert(value:emit("replay_reset", { reason = "test" }, 0))
        frame = begin(value)
        assertions.equal(false, frame.redraw)
        local reset = assert(value:transform_cell(visual_cell(), true))
        assert(value:end_visual_frame())
        assert(value:emit("output", { bytes = "A" }, 0))
        assert(value:advance(1000000))
        frame = begin(value)
        assertions.equal(false, frame.redraw)
        local decayed = assert(value:transform_cell(visual_cell(), true))
        assert(value:end_visual_frame())
        return active, reset, decayed
      end
      local first_active, first_reset, first_decayed = trace()
      local second_active, second_reset, second_decayed = trace()
      assertions.truthy(first_active.offset_x ~= 0 or first_active.offset_y ~= 0)
      assertions.equal(first_active.offset_x, second_active.offset_x)
      assertions.equal(first_active.offset_y, second_active.offset_y)
      for _, transform in ipairs({ first_reset, first_decayed, second_reset, second_decayed }) do
        assertions.equal(0, transform.offset_x)
        assertions.equal(0, transform.offset_y)
      end
    end,
  },
  {
    name = "kinetic isolates invalid transform failures and preserves later effects",
    run = function()
      local value = host({ failing_transform(), assert(Kinetic.new()) })
      assert(value:emit("output", { bytes = "A" }, 0))
      local frame = begin(value)
      assertions.equal(true, frame.redraw)
      local transform = assert(value:transform_cell(visual_cell(), true))
      assert(value:end_visual_frame())
      local status = value:status()
      assertions.equal(false, status.effects[1].enabled)
      assertions.equal("failure", status.effects[1].disabled_reason)
      assertions.equal(true, status.effects[2].enabled)
      assertions.truthy(transform.offset_x ~= 0 or transform.offset_y ~= 0)
    end,
  },
  {
    name = "kinetic renderer translation preserves terminal and recording state",
    run = function()
      local events = { assert(Event.output("A", 7)) }
      local bytes = recording(events)
      local direct = assert(Terminal.new({ columns = 2, rows = 1 }))
      assert(direct:feed_output("A"))
      local effect_host = host({ assert(Kinetic.new()) })
      local terminal = assert(Terminal.new({ columns = 2, rows = 1 }))
      local coordinator = assert(Coordinator.new(terminal, assert(Replay.new(source(bytes))), {
        effect_host = effect_host,
      }))
      assert(coordinator:update(7))
      local api = graphics()
      local renderer = assert(Renderer.new({ effect_host = effect_host }))
      assert(renderer:load_font(api))
      assert(renderer:draw_terminal(terminal))
      local printed
      for _, call in ipairs(api.calls) do
        if call.name == "print" and call[1] == "A" then
          printed = call
        end
      end
      assertions.truthy(printed)
      assertions.truthy(printed[2] > 0)
      assertions.equal(assert(direct:digest()), assert(terminal:digest()))
      assertions.equal(bytes, recording(events))
    end,
  },
}
