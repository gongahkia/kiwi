local assertions = require("support.assertions")
local Effect = require("effects.effect")
local Host = require("effects.host")
local Replay = require("backend.replay")
local Event = require("runtime.event")
local Frames = require("recording.frames")
local RecordingWriter = require("recording.writer")
local Terminal = require("terminal.terminal")

local function manifest(id, capabilities)
  return {
    api_version = 1,
    capabilities = capabilities or {},
    determinism = "deterministic",
    id = id,
    parameters = {},
    version = "0.1.0",
  }
end

local function canvas_runtime()
  local runtime = { operations = {}, restores = 0, saves = 0, state = "baseline" }
  function runtime:save()
    self.saves = self.saves + 1
    self.saved_state = self.state
    return true
  end
  function runtime:restore()
    self.restores = self.restores + 1
    self.state = self.saved_state
    return true
  end
  function runtime:draw(operation)
    self.operations[#self.operations + 1] = operation
    self.state = operation.kind
    return true
  end
  return runtime
end

local function source(bytes)
  local value = { bytes = bytes, offset = 1 }
  function value:read(count)
    if self.offset > #self.bytes then
      return nil
    end
    local finish = math.min(#self.bytes, self.offset + math.min(count, 3) - 1)
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

local function cell_source(cell, damage)
  return {
    attributes = cell.attributes,
    background = cell.background,
    column = 1,
    cursor = false,
    damage = damage,
    foreground = cell.foreground,
    row = 1,
    screen = "primary",
    text = cell.text,
    width = cell.width,
  }
end

return {
  {
    name = "effect host accepts effects with no optional hooks",
    run = function()
      local effect = assert(Effect.new(manifest("test.empty", { "terminal_events" })))
      local host = assert(Host.new({ effect }))
      assertions.truthy(host:update(0))
      assertions.truthy(host:shutdown())
      assertions.truthy(host:shutdown())
      assertions.truthy(host:status().effects[1].initialised)
    end,
  },
  {
    name = "effect host invokes capability-gated lifecycle hooks in order",
    run = function()
      local calls = {}
      local effect = assert(Effect.new(
        manifest("test.lifecycle", {
          "lifecycle",
          "terminal_events",
          "cell_observation",
          "canvas_before",
          "canvas_after",
          "frame_update",
        }),
        {
          after_canvas = function(_, context, canvas)
            calls[#calls + 1] = "after:" .. context.frame_sequence
            assert(canvas:draw("text", { text = "after", x = 1, y = 2 }))
          end,
          before_canvas = function(_, context, canvas)
            calls[#calls + 1] = "before:" .. context.frame_sequence
            assert(canvas:draw("fill_rect", { height = 2, width = 1, x = 0, y = 0 }))
          end,
          init = function(_, context)
            calls[#calls + 1] = "init:" .. context.api_version
          end,
          on_cell = function(_, _, cell)
            calls[#calls + 1] = "cell:" .. cell.text
          end,
          on_event = function(_, _, event)
            calls[#calls + 1] = "event:" .. event.kind
          end,
          shutdown = function()
            calls[#calls + 1] = "shutdown"
          end,
          update = function(_, _, delta_us)
            calls[#calls + 1] = "update:" .. delta_us
          end,
        }
      ))
      local runtime = canvas_runtime()
      local host = assert(Host.new({ effect }, {
        canvas_runtime = runtime,
        headless = false,
        terminal = { columns = 2, rows = 1 },
        viewport = { height = 20, width = 40 },
      }))
      assert(host:update(7))
      assert(host:emit("output", { bytes = "A" }, 7))
      assert(host:observe_cells({
        {
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
        },
      }, false))
      assert(host:before_canvas())
      assert(host:after_canvas())
      assert(host:shutdown())
      assert(host:shutdown())
      assertions.equal("init:1", calls[1])
      assertions.equal("update:7", calls[2])
      assertions.equal("event:output", calls[3])
      assertions.equal("cell:A", calls[4])
      assertions.equal("before:1", calls[5])
      assertions.equal("after:1", calls[6])
      assertions.equal("shutdown", calls[7])
      assertions.equal(nil, calls[8])
      assertions.equal(2, runtime.saves)
      assertions.equal(2, runtime.restores)
      assertions.equal("baseline", runtime.state)
      assertions.equal("fill_rect", runtime.operations[1].kind)
      assertions.equal("text", runtime.operations[2].kind)
    end,
  },
  {
    name = "effect host isolates context event and cell mutations from runtime state",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 1 }))
      assert(terminal:feed_output("A"))
      local backing = terminal.primary_screen.rows[1].cells[1]
      local observed = {}
      local mutator = assert(Effect.new(
        manifest("test.mutator", {
          "terminal_events",
          "cell_observation",
          "frame_update",
        }),
        {
          on_cell = function(_, context, cell)
            context.terminal.columns = 999
            cell.text = "changed"
            cell.foreground = { kind = "rgb", red = 0, green = 0, blue = 0 }
          end,
          on_event = function(_, context, event)
            context.viewport.width = 999
            event.payload.bytes = "changed"
          end,
          update = function(_, context)
            context.runtime.headless = false
          end,
        }
      ))
      local observer = assert(Effect.new(
        manifest("test.observer", {
          "terminal_events",
          "cell_observation",
          "frame_update",
        }),
        {
          on_cell = function(_, context, cell)
            observed.cell = cell.text
            observed.columns = context.terminal.columns
            observed.has_terminal = context.terminal.primary_screen ~= nil
            observed.has_parser = context.parser ~= nil
          end,
          on_event = function(_, context, event)
            observed.bytes = event.payload.bytes
            observed.width = context.viewport.width
            observed.has_renderer = context.renderer ~= nil
            observed.has_backend = context.backend ~= nil
            observed.has_process = context.process ~= nil
          end,
          update = function(_, context)
            observed.headless = context.runtime.headless
          end,
        }
      ))
      local host = assert(Host.new({ mutator, observer }, {
        terminal = { columns = 2, rows = 1 },
        viewport = { height = 20, width = 40 },
      }))
      assert(host:update(0))
      assert(host:emit("output", { bytes = "A" }, 0))
      assert(host:observe_cells({ cell_source(backing, true) }, false))
      assertions.equal("A", observed.bytes)
      assertions.equal(40, observed.width)
      assertions.equal("A", observed.cell)
      assertions.equal(2, observed.columns)
      assertions.equal(true, observed.headless)
      assertions.falsy(observed.has_terminal)
      assertions.falsy(observed.has_parser)
      assertions.falsy(observed.has_renderer)
      assertions.falsy(observed.has_backend)
      assertions.falsy(observed.has_process)
      assertions.equal("A", backing.text)
    end,
  },
  {
    name = "effect host rejects undeclared and headless canvas capabilities",
    run = function()
      local invalid, invalid_error = Effect.new(manifest("test.invalid"), {
        update = function() end,
      })
      assertions.falsy(invalid)
      assertions.equal("effect_load_error", invalid_error.kind)
      local canvas = assert(Effect.new(manifest("test.canvas", { "canvas_before" }), {
        before_canvas = function() end,
      }))
      local host, host_error = Host.new({ canvas })
      assertions.falsy(host)
      assertions.equal("effect_incompatible", host_error.kind)
    end,
  },
  {
    name = "effect host validates bounded integer microsecond deltas",
    run = function()
      local host = assert(Host.new({ assert(Effect.new(manifest("test.timing"))) }, {
        max_delta_us = 10,
      }))
      assert(host:update(10))
      for _, delta in ipairs({ -1, 0.5, 11 }) do
        local value, error_value = host:update(delta)
        assertions.falsy(value)
        assertions.equal("config_error", error_value.kind)
      end
    end,
  },
  {
    name = "effect host deterministically subdivides coordinator timing advances",
    run = function()
      local deltas = {}
      local effect = assert(Effect.new(manifest("test.advance", { "frame_update" }), {
        update = function(_, _, delta_us)
          deltas[#deltas + 1] = delta_us
        end,
      }))
      local host = assert(Host.new({ effect }, { max_delta_us = 10 }))
      assert(host:advance(25))
      assertions.equal(3, host:status().frame_sequence)
      assertions.equal(25, host:status().elapsed_us)
      assertions.equal(10, deltas[1])
      assertions.equal(10, deltas[2])
      assertions.equal(5, deltas[3])
      local value, error_value = host:advance(0.5)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
    end,
  },
  {
    name = "effect host enforces configured effect callback and payload limits",
    run = function()
      local first = assert(Effect.new(manifest("test.first")))
      local second = assert(Effect.new(manifest("test.second")))
      local host, host_error = Host.new({ first, second }, { max_effects = 1 })
      assertions.falsy(host)
      assertions.equal("config_error", host_error.kind)
      local payload_effect = assert(Effect.new(manifest("test.payload", { "terminal_events" })))
      host = assert(Host.new({ payload_effect }, {
        max_event_payload_bytes = 1,
      }))
      local event, event_error = host:emit("output", { bytes = "AB" }, 0)
      assertions.falsy(event)
      assertions.equal("config_error", event_error.kind)
    end,
  },
  {
    name = "effect host preserves stable ordering and replay-derived event timing",
    run = function()
      local function trace()
        local calls = {}
        local first =
          assert(Effect.new(manifest("test.first", { "terminal_events", "frame_update" }), {
            on_event = function(_, _, event)
              calls[#calls + 1] = "first:"
                .. event.sequence
                .. ":"
                .. event.timestamp_us
                .. ":"
                .. event.payload.bytes
            end,
            update = function() end,
          }))
        local second =
          assert(Effect.new(manifest("test.second", { "terminal_events", "frame_update" }), {
            on_event = function(_, _, event)
              calls[#calls + 1] = "second:"
                .. event.sequence
                .. ":"
                .. event.timestamp_us
                .. ":"
                .. event.payload.bytes
            end,
            update = function() end,
          }))
        local host = assert(Host.new({ first, second }))
        local replay = assert(Replay.new(source(recording({
          assert(Event.output("A", 4)),
          assert(Event.output("B", 6)),
        }))))
        assert(replay:start())
        for _, delta in ipairs({ 4, 6 }) do
          assert(host:update(delta))
          for _, event in ipairs(assert(replay:poll(delta))) do
            assert(host:emit("output", { bytes = event.data }, host:status().elapsed_us))
          end
        end
        return table.concat(calls, "|")
      end
      local first = trace()
      local second = trace()
      assertions.equal(first, second)
      assertions.equal("first:1:4:A|second:1:4:A|first:2:10:B|second:2:10:B", first)
    end,
  },
  {
    name = "effect host restores canvas state and contains callback failures",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 1 }))
      assert(terminal:feed_output("A"))
      local digest = assert(terminal:digest())
      local failing =
        assert(Effect.new(manifest("test.failing", { "terminal_events", "lifecycle" }), {
          on_event = function()
            error("test failure")
          end,
          shutdown = function() end,
        }))
      local healthy_events = 0
      local healthy = assert(Effect.new(manifest("test.healthy", { "terminal_events" }), {
        on_event = function()
          healthy_events = healthy_events + 1
        end,
      }))
      local host = assert(Host.new({ failing, healthy }))
      assert(host:update(0))
      assert(host:emit("output", { bytes = "A" }, 0))
      assertions.equal(1, healthy_events)
      assertions.falsy(host:status().effects[1].enabled)
      assertions.truthy(host:status().effects[2].enabled)
      assertions.equal(assert(terminal:digest()), digest)
      assertions.equal(1, #host:status().diagnostics)
    end,
  },
  {
    name = "effect host emits resize screen checkpoint and full-redraw cell lifecycle records",
    run = function()
      local kinds = {}
      local damage = {}
      local effect = assert(Effect.new(
        manifest("test.records", {
          "terminal_events",
          "cell_observation",
        }),
        {
          on_cell = function(_, _, cell)
            damage[#damage + 1] = cell.damage
          end,
          on_event = function(_, _, event)
            kinds[#kinds + 1] = event.kind
          end,
        }
      ))
      local host = assert(Host.new({ effect }, {
        terminal = { columns = 2, rows = 1 },
        viewport = { height = 20, width = 40 },
      }))
      assert(host:update(1))
      assert(host:resize({ height = 30, width = 60 }, { columns = 3, rows = 2 }, 1))
      assert(host:emit("screen_switch", { screen = "alternate" }, 1))
      assert(host:emit("checkpoint_restored", { checkpoint_us = 1 }, 1))
      assert(host:emit("replay_seek", { target_us = 1 }, 1))
      assert(host:emit("scroll", {
        bottom = 2,
        count = 1,
        direction = "up",
        top = 1,
      }, 1))
      local cell = {
        attributes = 0,
        background = "default",
        column = 1,
        cursor = false,
        damage = false,
        foreground = "default",
        row = 1,
        screen = "alternate",
        text = "A",
        width = 1,
      }
      assert(host:observe_cells({ cell }, false))
      assert(host:observe_cells({ cell }, true))
      assertions.equal("resize", kinds[1])
      assertions.equal("screen_switch", kinds[2])
      assertions.equal("checkpoint_restored", kinds[3])
      assertions.equal("replay_seek", kinds[4])
      assertions.equal("scroll", kinds[5])
      assertions.equal(false, damage[1])
      assertions.equal(true, damage[2])
    end,
  },
}
