local assertions = require("support.assertions")
local Clean = require("effects.clean")
local Coordinator = require("runtime.coordinator")
local CRT = require("effects.crt")
local Effect = require("effects.effect")
local Event = require("runtime.event")
local Frames = require("recording.frames")
local Host = require("effects.host")
local RecordingWriter = require("recording.writer")
local Replay = require("backend.replay")
local Terminal = require("terminal.terminal")

local function canvas_runtime()
  local runtime = { operations = {} }
  function runtime:save()
    return true
  end
  function runtime:restore()
    return true
  end
  function runtime:draw(operation)
    self.operations[#self.operations + 1] = operation
    return true
  end
  return runtime
end

local function host(effects, runtime)
  return assert(Host.new(effects, {
    canvas_runtime = runtime,
    headless = false,
    terminal = { columns = 4, rows = 2 },
    viewport = { height = 12, width = 24 },
  }))
end

local function operation_signature(operations)
  local values = {}
  for _, operation in ipairs(operations) do
    local colour = operation.colour
    values[#values + 1] = table.concat({
      operation.kind,
      operation.x or "",
      operation.y or "",
      operation.width or "",
      operation.height or "",
      colour and colour.red or "",
      colour and colour.green or "",
      colour and colour.blue or "",
      colour and colour.alpha or "",
    }, ":")
  end
  return table.concat(values, "|")
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

local function failing_effect()
  return assert(Effect.new({
    api_version = 1,
    capabilities = { "canvas_after" },
    determinism = "deterministic",
    id = "test.crt-failure",
    parameters = {},
    version = "0.1.0",
  }, {
    after_canvas = function()
      error("expected failure")
    end,
  }))
end

return {
  {
    name = "CRT declares bounded deterministic public capabilities and parameters",
    run = function()
      local effect = assert(CRT.new())
      local manifest = effect:manifest()
      assertions.equal(CRT.id, manifest.id)
      assertions.equal("deterministic", manifest.determinism)
      assertions.equal("terminal_events", manifest.capabilities[1])
      assertions.equal("canvas_after", manifest.capabilities[2])
      assertions.equal("frame_update", manifest.capabilities[3])
      assertions.equal(0, manifest.parameters.intensity.min)
      assertions.equal(1, manifest.parameters.intensity.max)
      assertions.equal(0, manifest.parameters.bloom.min)
      assertions.equal(0.5, manifest.parameters.bloom.max)
      assertions.equal(2, manifest.parameters.scanline_spacing.min)
      assertions.equal(8, manifest.parameters.scanline_spacing.max)
      local invalid, invalid_error = CRT.new({ intensity = 1.01 })
      assertions.falsy(invalid)
      assertions.equal("effect_load_error", invalid_error.kind)
      invalid, invalid_error = CRT.new({ scanline_spacing = 1 })
      assertions.falsy(invalid)
      assertions.equal("effect_load_error", invalid_error.kind)
      assert(effect:set_parameters({ intensity = 0.8, reduced_motion = true }))
      invalid, invalid_error = effect:set_parameters({ bloom = 0.6 })
      assertions.falsy(invalid)
      assertions.equal("effect_load_error", invalid_error.kind)
      assertions.equal(0.8, effect:parameters().intensity)
      assertions.equal(true, effect:parameters().reduced_motion)
    end,
  },
  {
    name = "CRT resets temporal state deterministically without retained frame buffers",
    run = function()
      local function trace()
        local runtime = canvas_runtime()
        local value = host({ assert(CRT.new({ persistence = 0.5 })) }, runtime)
        assert(value:advance(100000))
        assert(value:emit("output", { bytes = "A" }, 100000))
        assert(value:after_canvas())
        local active = operation_signature(runtime.operations)
        runtime.operations = {}
        assert(value:emit("replay_reset", { reason = "test" }, 100000))
        assert(value:after_canvas())
        return active, operation_signature(runtime.operations)
      end
      local first_active, first_reset = trace()
      local second_active, second_reset = trace()
      assertions.truthy(first_active ~= "")
      assertions.equal(first_active, second_active)
      assertions.equal(first_reset, second_reset)
      local runtime = canvas_runtime()
      local baseline = host({ assert(CRT.new({ persistence = 0.5 })) }, runtime)
      assert(baseline:after_canvas())
      assertions.equal(operation_signature(runtime.operations), first_reset)
    end,
  },
  {
    name = "CRT remains active when another canvas effect fails",
    run = function()
      local runtime = canvas_runtime()
      local value = host({ failing_effect(), assert(CRT.new()) }, runtime)
      assert(value:after_canvas())
      local status = value:status()
      assertions.equal(false, status.effects[1].enabled)
      assertions.equal("failure", status.effects[1].disabled_reason)
      assertions.equal(true, status.effects[2].enabled)
      assertions.truthy(#runtime.operations > 0)
    end,
  },
  {
    name = "CRT lifecycle observations preserve terminal and recording state",
    run = function()
      local events = { assert(Event.output("A", 7)) }
      local bytes = recording(events)
      local direct = assert(Terminal.new({ columns = 4, rows = 2 }))
      assert(direct:feed_output("A"))
      local runtime = canvas_runtime()
      local effect_host = host({ assert(CRT.new()) }, runtime)
      local terminal = assert(Terminal.new({ columns = 4, rows = 2 }))
      local coordinator = assert(Coordinator.new(terminal, assert(Replay.new(source(bytes))), {
        effect_host = effect_host,
      }))
      assert(coordinator:update(7))
      assert(effect_host:after_canvas())
      assertions.equal(assert(direct:digest()), assert(terminal:digest()))
      assertions.equal(bytes, recording(events))
    end,
  },
  {
    name = "clean reset disables visual effects and restores the baseline chain",
    run = function()
      local runtime = canvas_runtime()
      local clean = assert(Clean.new())
      local value = host({ clean, assert(CRT.new()) }, runtime)
      assert(value:disable(Clean.id))
      assert(Clean.reset(value))
      local status = value:status()
      assertions.equal(true, status.effects[1].enabled)
      assertions.equal(false, status.effects[2].enabled)
      assert(value:after_canvas())
      assertions.equal(0, #runtime.operations)
      assert(Clean.reset(value))
    end,
  },
}
