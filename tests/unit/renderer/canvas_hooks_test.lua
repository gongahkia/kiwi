local assertions = require("support.assertions")
local Coordinator = require("runtime.coordinator")
local Effect = require("effects.effect")
local Host = require("effects.host")
local Event = require("runtime.event")
local FontFixture = require("fixtures.renderer.font")
local Frames = require("recording.frames")
local RecordingWriter = require("recording.writer")
local Renderer = require("renderer.renderer")
local Replay = require("backend.replay")
local Terminal = require("terminal.terminal")

local function manifest(id, capabilities, determinism)
  return {
    api_version = 1,
    capabilities = capabilities or {},
    determinism = determinism or "deterministic",
    id = id,
    parameters = {},
    version = "0.1.0",
  }
end

local function effect(id, capabilities, hooks, determinism)
  return assert(Effect.new(manifest(id, capabilities, determinism), hooks))
end

local function copy_state(state)
  local result = {}
  for name, value in pairs(state) do
    if type(value) == "table" then
      result[name] = {}
      for index, nested in pairs(value) do
        result[name][index] = nested
      end
    else
      result[name] = value
    end
  end
  return result
end

local function graphics()
  local api = { calls = {}, new_canvas_calls = 0 }
  local state = {
    alpha_mode = "alphamultiply",
    blend_mode = "alpha",
    canvas = "caller-canvas",
    color = { 0.2, 0.3, 0.4, 0.5 },
    depth_mode = "less",
    depth_write = true,
    font = "caller-font",
    line_style = "rough",
    line_width = 3,
    mesh_cull_mode = "back",
    point_size = 4,
    scissor = { 1, 2, 30, 40 },
    shader = "caller-shader",
    stencil_compare = "equal",
    stencil_value = 2,
    transform = 0,
  }
  local stack = {}
  local function record(name, ...)
    api.calls[#api.calls + 1] = { name = name, ... }
  end
  function api.newFont(path_or_size, size)
    record("newFont", path_or_size, size)
    return FontFixture.new()
  end
  function api.push(mode)
    record("push", mode)
    stack[#stack + 1] = copy_state(state)
  end
  function api.pop()
    record("pop")
    local saved = stack[#stack]
    if not saved then
      error("unbalanced graphics state")
    end
    stack[#stack] = nil
    state = saved
  end
  function api.getCanvas()
    return state.canvas
  end
  function api.setCanvas(value)
    record("setCanvas", value)
    state.canvas = value
  end
  function api.getShader()
    return state.shader
  end
  function api.setShader(value)
    record("setShader", value)
    state.shader = value
  end
  function api.getBlendMode()
    return state.blend_mode, state.alpha_mode
  end
  function api.setBlendMode(mode, alpha_mode)
    record("setBlendMode", mode, alpha_mode)
    state.blend_mode = mode
    state.alpha_mode = alpha_mode
  end
  function api.getColor()
    return state.color[1], state.color[2], state.color[3], state.color[4]
  end
  function api.setColor(red, green, blue, alpha)
    record("setColor", red, green, blue, alpha)
    state.color = { red, green, blue, alpha }
  end
  function api.getScissor()
    if state.scissor then
      return state.scissor[1], state.scissor[2], state.scissor[3], state.scissor[4]
    end
  end
  function api.setScissor(x, y, width, height)
    record("setScissor", x, y, width, height)
    state.scissor = x and { x, y, width, height } or nil
  end
  function api.getStencilTest()
    return state.stencil_compare, state.stencil_value
  end
  function api.setStencilTest(compare, value)
    record("setStencilTest", compare, value)
    state.stencil_compare = compare
    state.stencil_value = value
  end
  function api.getFont()
    return state.font
  end
  function api.setFont(value)
    record("setFont", value)
    state.font = value
  end
  function api.getLineWidth()
    return state.line_width
  end
  function api.setLineWidth(value)
    record("setLineWidth", value)
    state.line_width = value
  end
  function api.getLineStyle()
    return state.line_style
  end
  function api.setLineStyle(value)
    record("setLineStyle", value)
    state.line_style = value
  end
  function api.getPointSize()
    return state.point_size
  end
  function api.setPointSize(value)
    record("setPointSize", value)
    state.point_size = value
  end
  function api.getDepthMode()
    return state.depth_mode, state.depth_write
  end
  function api.setDepthMode(mode, write)
    record("setDepthMode", mode, write)
    state.depth_mode = mode
    state.depth_write = write
  end
  function api.getMeshCullMode()
    return state.mesh_cull_mode
  end
  function api.setMeshCullMode(value)
    record("setMeshCullMode", value)
    state.mesh_cull_mode = value
  end
  function api.translate(x, y)
    record("translate", x, y)
    state.transform = state.transform + x + y
  end
  function api.rectangle(mode, x, y, width, height)
    record("rectangle", mode, x, y, width, height)
  end
  function api.line(x1, y1, x2, y2)
    record("line", x1, y1, x2, y2)
  end
  function api.print(text, x, y)
    record("print", text, x, y)
    if api.on_print then
      api.on_print(text)
    end
  end
  function api:state()
    local copied = copy_state(state)
    copied.stack_depth = #stack
    return copied
  end
  return api
end

local function same_state(expected, actual)
  for name, value in pairs(expected) do
    if type(value) == "table" then
      for index, nested in pairs(value) do
        assertions.equal(nested, actual[name][index], name .. ":" .. index)
      end
    else
      assertions.equal(value, actual[name], name)
    end
  end
end

local function terminal(columns, rows)
  local value = assert(Terminal.new({ columns = columns or 2, rows = rows or 1 }))
  assert(value:feed_output("T"))
  return value
end

local function setup(effects, options)
  options = options or {}
  local api = graphics()
  local host = assert(Host.new(effects, {
    headless = false,
    max_draw_operations = options.max_draw_operations,
    random_seed = options.random_seed or 7,
    terminal = { columns = 2, rows = 1 },
    viewport = { height = 17, width = 18 },
  }))
  local renderer = assert(Renderer.new({ effect_host = host }))
  assert(renderer:load_font(api))
  return api, host, renderer, terminal()
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

return {
  {
    name = "renderer preserves the clean path when no canvas-capable effects are enabled",
    run = function()
      local plain_api = graphics()
      local plain = assert(Renderer.new({}))
      assert(plain:load_font(plain_api))
      assert(plain:draw_terminal(terminal()))
      local host_api, host, renderer, value = setup({})
      assert(renderer:draw_terminal(value))
      assertions.equal(#plain_api.calls, #host_api.calls)
      assertions.equal(0, host:status().canvas_frame_sequence or 0)
    end,
  },
  {
    name = "renderer invokes canvas phases once in stable chain order around terminal rendering",
    run = function()
      local calls = {}
      local first = effect("test.canvas-first", { "canvas_before", "canvas_after" }, {
        after_canvas = function(_, context)
          calls[#calls + 1] = "first-after:" .. context.frame_sequence
        end,
        before_canvas = function(_, context, canvas)
          calls[#calls + 1] = "first-before:" .. context.frame_sequence
          assert(canvas:fill_rect(0, 0, 1, 1))
        end,
      })
      local second = effect("test.canvas-second", { "canvas_before", "canvas_after" }, {
        after_canvas = function(_, context)
          calls[#calls + 1] = "second-after:" .. context.frame_sequence
        end,
        before_canvas = function(_, context)
          calls[#calls + 1] = "second-before:" .. context.frame_sequence
        end,
      })
      local api, host, renderer, value = setup({ first, second })
      api.on_print = function(text)
        calls[#calls + 1] = "terminal:" .. text
      end
      assert(renderer:draw_terminal(value))
      assertions.equal("first-before:1", calls[1])
      assertions.equal("second-before:1", calls[2])
      assertions.equal("terminal:T", calls[3])
      assertions.equal("first-after:1", calls[4])
      assertions.equal("second-after:1", calls[5])
      assertions.equal(nil, calls[6])
      assert(host:reorder({ "test.canvas-second", "test.canvas-first" }))
      assert(renderer:draw_terminal(value))
      assertions.equal("second-before:2", calls[6])
      assertions.equal("first-before:2", calls[7])
      assert(host:disable("test.canvas-second"))
      assert(renderer:draw_terminal(value))
      assertions.equal("first-before:3", calls[11])
    end,
  },
  {
    name = "renderer invokes only the declared single canvas phase once per eligible frame",
    run = function()
      local before_calls = 0
      local after_calls = 0
      local before = effect("test.canvas-before-only", { "canvas_before" }, {
        before_canvas = function()
          before_calls = before_calls + 1
        end,
      })
      local after = effect("test.canvas-after-only", { "canvas_after" }, {
        after_canvas = function()
          after_calls = after_calls + 1
        end,
      })
      local _, _, renderer, value = setup({ before, after })
      assert(renderer:draw_terminal(value))
      assert(renderer:draw_terminal(value))
      assertions.equal(2, before_calls)
      assertions.equal(2, after_calls)
    end,
  },
  {
    name = "renderer isolates successful and throwing canvas hooks without state leakage",
    run = function()
      local calls = {}
      local api
      local mutating = effect("test.canvas-mutating", { "canvas_before" }, {
        before_canvas = function(_, _, canvas)
          api.setCanvas("effect-canvas")
          api.setShader("effect-shader")
          api.setBlendMode("add", "premultiplied")
          api.setColor(1, 0, 0, 1)
          api.setScissor(0, 0, 1, 1)
          api.setStencilTest("greater", 1)
          api.setFont("effect-font")
          api.setLineWidth(9)
          api.setLineStyle("smooth")
          api.setPointSize(8)
          api.setDepthMode("greater", false)
          api.setMeshCullMode("front")
          api.translate(4, 5)
          assert(canvas:line(0, 0, 1, 1))
        end,
      })
      local throwing = effect("test.canvas-throwing", { "canvas_before" }, {
        before_canvas = function()
          api.setCanvas("broken-canvas")
          api.setColor(0, 1, 0, 1)
          api.translate(2, 3)
          error("expected canvas failure")
        end,
      })
      local healthy = effect("test.canvas-healthy", { "canvas_before" }, {
        before_canvas = function()
          calls[#calls + 1] = api:state().canvas
        end,
      })
      api, host, renderer, value = setup({ mutating, throwing, healthy })
      local initial = api:state()
      api.on_print = function(text)
        calls[#calls + 1] = "terminal:" .. text
      end
      assert(renderer:draw_terminal(value))
      same_state(initial, api:state())
      assertions.equal("caller-canvas", calls[1])
      assertions.equal("terminal:T", calls[2])
      assertions.equal(false, host:status().effects[2].enabled)
      assertions.equal("failure", host:status().effects[2].disabled_reason)
      assertions.equal("test.canvas-throwing", host:status().diagnostics[1].effect_id)
      assertions.equal("before_canvas", host:status().diagnostics[1].hook)
      assertions.equal("effect_runtime_error", host:status().diagnostics[1].kind)
      assertions.truthy(host:status().diagnostics[1].detail.cause ~= nil)
      assert(renderer:draw_terminal(value))
      same_state(initial, api:state())
      assertions.equal("caller-canvas", calls[3])
    end,
  },
  {
    name = "renderer contains failing after hooks and preserves later frames",
    run = function()
      local calls = {}
      local api
      local failing = effect("test.canvas-after-failure", { "canvas_after" }, {
        after_canvas = function()
          api.setCanvas("after-canvas")
          api.setShader("after-shader")
          error("expected after failure")
        end,
      })
      local healthy = effect("test.canvas-after-healthy", { "canvas_after" }, {
        after_canvas = function()
          calls[#calls + 1] = "healthy-after"
        end,
      })
      api, host, renderer, value = setup({ failing, healthy })
      api.on_print = function(text)
        calls[#calls + 1] = "terminal:" .. text
      end
      local initial = api:state()
      assert(renderer:draw_terminal(value))
      same_state(initial, api:state())
      assertions.equal("terminal:T", calls[1])
      assertions.equal("healthy-after", calls[2])
      assertions.equal(false, host:status().effects[1].enabled)
      assertions.equal("after_canvas", host:status().diagnostics[1].hook)
      assert(renderer:draw_terminal(value))
      same_state(initial, api:state())
      assertions.equal("terminal:T", calls[3])
      assertions.equal("healthy-after", calls[4])
    end,
  },
  {
    name = "renderer quarantines invalid bounded drawing and retains no canvas resources",
    run = function()
      local retained
      local limited = effect("test.canvas-limit", { "canvas_before" }, {
        before_canvas = function(_, _, canvas)
          retained = canvas
          assert(canvas:fill_rect(0, 0, 1, 1))
          canvas:fill_rect(1, 0, 1, 1)
        end,
      })
      local healthy_calls = 0
      local healthy = effect("test.canvas-limit-healthy", { "canvas_before" }, {
        before_canvas = function()
          healthy_calls = healthy_calls + 1
        end,
      })
      local api, host, renderer, value = setup({ limited, healthy }, { max_draw_operations = 1 })
      local initial = api:state()
      assert(renderer:draw_terminal(value))
      same_state(initial, api:state())
      assertions.equal(false, host:status().effects[1].enabled)
      assertions.equal("effect_runtime_error", host:status().diagnostics[1].kind)
      assertions.equal(
        "effect canvas draw operation limit exceeded",
        host:status().diagnostics[1].message
      )
      local expired, expired_error = retained:fill_rect(0, 0, 1, 1)
      assertions.falsy(expired)
      assertions.equal("effect_runtime_error", expired_error.kind)
      for _ = 1, 32 do
        assert(renderer:draw_terminal(value))
        same_state(initial, api:state())
      end
      assertions.equal(33, healthy_calls)
      assertions.equal(0, api.new_canvas_calls)
      assertions.equal(0, renderer.canvas_runtime:stats().allocations)
      assertions.equal(0, renderer.canvas_runtime:stats().state_depth)
    end,
  },
  {
    name = "renderer rejects undeclared and headless canvas hooks before rendering",
    run = function()
      local invalid, invalid_error = Effect.new(manifest("test.canvas-undeclared"), {
        before_canvas = function() end,
      })
      assertions.falsy(invalid)
      assertions.equal("effect_load_error", invalid_error.kind)
      local canvas = effect("test.canvas-headless", { "canvas_before" }, {
        before_canvas = function() end,
      })
      local host, host_error = Host.new({ canvas })
      assertions.falsy(host)
      assertions.equal("effect_incompatible", host_error.kind)
    end,
  },
  {
    name = "renderer canvas hooks preserve terminal and recording semantics under deterministic replay",
    run = function()
      local function trace()
        local hooks = {}
        local visual = effect("test.canvas-replay", { "canvas_before", "deterministic_random" }, {
          before_canvas = function(_, context)
            hooks[#hooks + 1] = table.concat({
              context.effect_id,
              context.frame_sequence,
              context.elapsed_us,
              context.terminal.columns,
              context.viewport.width,
              context.random:next_u32(),
            }, ":")
          end,
        })
        local api, host, renderer, value = setup({ visual }, { random_seed = 9 })
        local events = {
          assert(Event.output("A", 4)),
          assert(Event.output("B", 6)),
        }
        local bytes = recording(events)
        local coordinator = assert(Coordinator.new(value, assert(Replay.new(source(bytes))), {
          effect_host = host,
        }))
        local first_batch = assert(coordinator:update(4))
        local first_semantic = assert(value:digest())
        assert(renderer:draw_terminal(value))
        assertions.equal(first_semantic, assert(value:digest()))
        assertions.equal("A", first_batch[1].event.data)
        local second_batch = assert(coordinator:update(6))
        local second_semantic = assert(value:digest())
        assert(renderer:draw_terminal(value))
        assertions.equal(second_semantic, assert(value:digest()))
        assertions.equal("B", second_batch[1].event.data)
        local after = assert(value:digest())
        assertions.truthy(after ~= "")
        assertions.equal(0, #host:status().diagnostics)
        return table.concat(hooks, "|"), after, bytes, api:state()
      end
      local first_trace, first_digest, first_bytes, first_state = trace()
      local second_trace, second_digest, second_bytes, second_state = trace()
      assertions.equal(first_trace, second_trace)
      assertions.equal(first_digest, second_digest)
      assertions.equal(first_bytes, second_bytes)
      same_state(first_state, second_state)
    end,
  },
  {
    name = "renderer supplies immutable resized viewport contexts at frame boundaries",
    run = function()
      local contexts = {}
      local visual = effect("test.canvas-resize", { "canvas_before" }, {
        before_canvas = function(_, context)
          contexts[#contexts + 1] = table.concat({
            context.frame_sequence,
            context.terminal.columns,
            context.terminal.rows,
            context.viewport.width,
            context.viewport.height,
          }, ":")
          context.terminal.columns = 999
          context.viewport.width = 999
        end,
      })
      local _, _, renderer, value = setup({ visual })
      assert(renderer:draw_terminal(value))
      assert(value:resize(3, 2))
      assert(renderer:resize(27, 34))
      assert(renderer:draw_terminal(value))
      assertions.equal("1:2:1:18:17", contexts[1])
      assertions.equal("2:3:2:27:34", contexts[2])
    end,
  },
  {
    name = "renderer generated canvas lifecycle controls preserve state and semantic invariants",
    run = function()
      local first = effect("test.canvas-generated-first", { "canvas_before" }, {
        before_canvas = function(_, _, canvas)
          assert(canvas:fill_rect(0, 0, 1, 1))
        end,
      })
      local second = effect("test.canvas-generated-second", { "canvas_after" }, {
        after_canvas = function(_, _, canvas)
          assert(canvas:text("x", 0, 0))
        end,
      })
      local api, host, renderer, value = setup({ first, second })
      local initial = api:state()
      local digest = assert(value:digest())
      for _ = 1, 128 do
        local action = math.random(1, 4)
        if action == 1 then
          assert(host:disable("test.canvas-generated-first"))
        elseif action == 2 then
          assert(host:enable("test.canvas-generated-first"))
        elseif action == 3 then
          assert(host:reorder({ "test.canvas-generated-second", "test.canvas-generated-first" }))
        else
          assert(host:reorder({ "test.canvas-generated-first", "test.canvas-generated-second" }))
        end
        assert(renderer:draw_terminal(value))
        same_state(initial, api:state())
        assertions.equal(digest, assert(value:digest()))
      end
      assertions.equal(0, renderer.canvas_runtime:stats().state_depth)
    end,
  },
}
