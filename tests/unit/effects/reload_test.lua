local assertions = require("support.assertions")
local Effect = require("effects.effect")
local Host = require("effects.host")
local Event = require("runtime.event")
local Frames = require("recording.frames")
local RecordingWriter = require("recording.writer")
local Terminal = require("terminal.terminal")

local function manifest(id, capabilities, parameters, version)
  return {
    api_version = 1,
    capabilities = capabilities or {},
    determinism = "deterministic",
    id = id,
    parameters = parameters or {},
    version = version or "0.1.0",
  }
end

local function effect(id, capabilities, parameters, hooks, version)
  return assert(Effect.new(manifest(id, capabilities, parameters, version), hooks))
end

local function migration_reason(host, parameter)
  for _, diagnostic in ipairs(host:status().diagnostics) do
    if
      diagnostic.kind == "effect_reload_migration" and diagnostic.detail.parameter == parameter
    then
      return diagnostic.detail.reason
    end
  end
  return nil
end

local function random_effect(id, state)
  return effect(id, { "deterministic_random", "lifecycle", "terminal_events" }, {}, {
    init = function()
      state.init = state.init + 1
    end,
    on_event = function(_, context)
      state.values[#state.values + 1] = context.random:next_u32()
    end,
    shutdown = function()
      state.shutdown = state.shutdown + 1
    end,
  })
end

return {
  {
    name = "effect replacement preserves logical slot state and metadata",
    run = function()
      local trace = {}
      local old_state = { shutdown = 0 }
      local left = effect("test.left", { "terminal_events" }, {}, {
        on_event = function()
          trace[#trace + 1] = "left"
        end,
      })
      local old = effect("test.reload", { "lifecycle", "terminal_events" }, {}, {
        on_event = function()
          trace[#trace + 1] = "old"
        end,
        shutdown = function()
          old_state.shutdown = old_state.shutdown + 1
        end,
      })
      local right = effect("test.right", { "terminal_events" }, {}, {
        on_event = function()
          trace[#trace + 1] = "right"
        end,
      })
      local candidate = effect("test.reload", { "lifecycle", "terminal_events" }, {}, {
        init = function()
          trace[#trace + 1] = "candidate:init"
        end,
        on_event = function()
          trace[#trace + 1] = "candidate"
        end,
      }, "0.2.0")
      local host = assert(Host.new({ left, old, right }, {
        effect_metadata = {
          ["test.reload"] = { label = "Reload target", source_identity = "source-v1" },
        },
      }))
      assert(host:disable("test.reload"))
      assert(host:replace("test.reload", candidate, { source_identity = "source-v2" }))
      local status = host:status()
      assertions.equal("test.left", status.effects[1].id)
      assertions.equal("test.reload", status.effects[2].id)
      assertions.equal("test.right", status.effects[3].id)
      assertions.falsy(status.effects[2].enabled)
      assertions.equal("manual", status.effects[2].disabled_reason)
      assertions.equal(1, status.effects[2].reload_generation)
      assertions.equal("Reload target", status.effects[2].metadata.label)
      assertions.equal("source-v2", status.effects[2].metadata.source_identity)
      assertions.equal(1, old_state.shutdown)
      assert(host:enable("test.reload"))
      assert(host:emit("output", { bytes = "A" }, 0))
      assertions.equal("candidate:init", trace[1])
      assertions.equal("left", trace[2])
      assertions.equal("candidate", trace[3])
      assertions.equal("right", trace[4])
    end,
  },
  {
    name = "effect replacement migrates only compatible bounded parameters",
    run = function()
      local old = effect("test.parameters", {}, {
        dropped = { default = 1, max = 10, min = 0, type = "integer" },
        invalid = { default = 1, max = 10, min = 0, type = "integer" },
        keep = { default = 1, max = 10, min = 0, type = "integer" },
        changed = { default = "old", max_length = 8, type = "string" },
      })
      assert(old:set_parameters({ changed = "kept", dropped = 4, invalid = 8, keep = 7 }))
      local candidate = effect("test.parameters", {}, {
        added = { default = true, type = "boolean" },
        invalid = { default = 3, max = 5, min = 0, type = "integer" },
        keep = { default = 2, max = 10, min = 0, type = "integer" },
        changed = { default = 9, max = 10, min = 0, type = "integer" },
      }, nil, "0.2.0")
      local host = assert(Host.new({ old }))
      assert(host:replace("test.parameters", candidate))
      local values = candidate:parameters()
      assertions.equal(true, values.added)
      assertions.equal(3, values.invalid)
      assertions.equal(7, values.keep)
      assertions.equal(9, values.changed)
      assertions.equal("removed", migration_reason(host, "dropped"))
      assertions.equal("invalid", migration_reason(host, "invalid"))
      assertions.equal("type_changed", migration_reason(host, "changed"))
      assertions.equal("new_default", migration_reason(host, "added"))
    end,
  },
  {
    name = "effect replacement retains the active instance when preparation fails",
    run = function()
      local observed = {}
      local old = effect("test.prepare", { "lifecycle", "terminal_events" }, {}, {
        on_event = function()
          observed[#observed + 1] = "old"
        end,
      })
      local host = assert(Host.new({ old }))
      local invalid = {
        manifest = function()
          return { id = "test.prepare" }
        end,
      }
      local replaced, replace_error = host:replace("test.prepare", invalid)
      assertions.falsy(replaced)
      assertions.equal("effect_reload_error", replace_error.kind)
      local init_state = { calls = 0 }
      local failing_init = effect("test.prepare", { "lifecycle", "terminal_events" }, {}, {
        init = function()
          init_state.calls = init_state.calls + 1
          error("candidate init failure")
        end,
      }, "0.2.0")
      replaced, replace_error = host:replace("test.prepare", failing_init)
      assertions.falsy(replaced)
      assertions.equal("effect_reload_error", replace_error.kind)
      assertions.equal(1, init_state.calls)
      assert(host:emit("output", { bytes = "A" }, 0))
      assertions.equal("old", observed[1])
      assertions.equal(nil, observed[2])
    end,
  },
  {
    name = "effect replacement isolates old shutdown failure and revalidates capabilities",
    run = function()
      local old_state = { shutdown = 0 }
      local new_state = { events = 0 }
      local old = effect("test.shutdown", { "lifecycle", "terminal_events" }, {}, {
        shutdown = function()
          old_state.shutdown = old_state.shutdown + 1
          error("old shutdown failure")
        end,
      })
      local candidate = effect("test.shutdown", { "terminal_events" }, {}, {
        on_event = function()
          new_state.events = new_state.events + 1
        end,
      }, "0.2.0")
      local host = assert(Host.new({ old }))
      assert(host:replace("test.shutdown", candidate))
      assert(host:emit("output", { bytes = "A" }, 0))
      assertions.equal(1, old_state.shutdown)
      assertions.equal(1, new_state.events)
      assertions.truthy(host:status().effects[1].enabled)
      local transform = effect("test.shutdown", { "cell_transform" }, {}, {
        transform_cell = function()
          return nil
        end,
      }, "0.3.0")
      local replaced, replace_error = host:replace("test.shutdown", transform)
      assertions.falsy(replaced)
      assertions.equal("effect_reload_error", replace_error.kind)
      assert(host:emit("output", { bytes = "B" }, 0))
      assertions.equal(2, new_state.events)
    end,
  },
  {
    name = "effect replacement occurs only at a quiescent boundary",
    run = function()
      local host
      local candidate_state = { events = 0 }
      local candidate = effect("test.boundary", { "terminal_events" }, {}, {
        on_event = function()
          candidate_state.events = candidate_state.events + 1
        end,
      }, "0.2.0")
      local old_state = { events = 0, rejected = nil }
      local old = effect("test.boundary", { "terminal_events" }, {}, {
        on_event = function()
          old_state.events = old_state.events + 1
          local replaced, replace_error = host:replace("test.boundary", candidate)
          old_state.rejected = replaced == nil and replace_error.kind
        end,
      })
      host = assert(Host.new({ old }))
      assert(host:emit("output", { bytes = "A" }, 0))
      assertions.equal("effect_reload_error", old_state.rejected)
      assertions.equal(1, old_state.events)
      assertions.equal(0, candidate_state.events)
      assert(host:replace("test.boundary", candidate))
      assert(host:emit("output", { bytes = "B" }, 0))
      assertions.equal(1, candidate_state.events)

      local transform = effect("test.visual-boundary", { "cell_transform" }, {}, {
        transform_cell = function()
          return nil
        end,
      })
      local visual_candidate = effect("test.visual-boundary", { "cell_transform" }, {}, {
        transform_cell = function()
          return nil
        end,
      }, "0.2.0")
      local visual_host = assert(Host.new({ transform }))
      assert(visual_host:begin_visual_frame({
        terminal = { columns = 1, rows = 1 },
        viewport = { height = 1, width = 1 },
      }))
      local replaced, replace_error = visual_host:replace("test.visual-boundary", visual_candidate)
      assertions.falsy(replaced)
      assertions.equal("effect_reload_error", replace_error.kind)
      assert(visual_host:end_visual_frame())
    end,
  },
  {
    name = "effect replacement resets local state and deterministic random streams",
    run = function()
      local function run()
        local old_state = { init = 0, shutdown = 0, values = {} }
        local first_state = { init = 0, shutdown = 0, values = {} }
        local second_state = { init = 0, shutdown = 0, values = {} }
        local host = assert(Host.new({ random_effect("test.random-reload", old_state) }, {
          random_seed = 44,
        }))
        assert(host:emit("output", { bytes = "A" }, 0))
        assert(host:replace("test.random-reload", random_effect("test.random-reload", first_state)))
        assert(host:emit("output", { bytes = "B" }, 0))
        assert(
          host:replace("test.random-reload", random_effect("test.random-reload", second_state))
        )
        assert(host:emit("output", { bytes = "C" }, 0))
        return {
          first = first_state.values[1],
          second = second_state.values[1],
          trace = table.concat({
            old_state.init,
            old_state.shutdown,
            first_state.init,
            first_state.shutdown,
            second_state.init,
          }, ":"),
        }
      end
      local first = run()
      local second = run()
      assertions.equal(first.first, first.second)
      assertions.equal(first.first, second.first)
      assertions.equal(first.second, second.second)
      assertions.equal(first.trace, second.trace)
      assertions.equal("1:1:1:1:1", first.trace)
    end,
  },
  {
    name = "effect replacement cannot mutate terminal semantics or recording input",
    run = function()
      local terminal = assert(Terminal.new({ columns = 2, rows = 1 }))
      local old = effect("test.recording-isolation", {}, {})
      local candidate = effect("test.recording-isolation", {}, {}, nil, "0.2.0")
      local host = assert(Host.new({ old }))
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
      assert(writer:append(assert(Frames.from_event(assert(Event.output("A", 1))))))
      local before = assert(terminal:digest())
      local recording = table.concat(sink.chunks)
      assert(host:replace("test.recording-isolation", candidate, {
        source_identity = "candidate-v2",
      }))
      assertions.equal(before, assert(terminal:digest()))
      assertions.equal(recording, table.concat(sink.chunks))
      assert(writer:close())
    end,
  },
}
