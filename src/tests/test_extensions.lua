local Assert = require("tests.assert")
local Extensions = require("kiwi.renderer.extensions")
local Registry = require("kiwi.renderer.pass_registry")

local function core_pass(name, order, events, after)
  return {
    name = name,
    order = order,
    reads = {},
    writes = {},
    after = after or {},
    initialize = function() events[#events + 1] = name .. "-initialize" end,
    encode = function() events[#events + 1] = name .. "-encode" end,
    shutdown = function() events[#events + 1] = name .. "-shutdown" end,
  }
end

local function core_passes(events)
  return {
    core_pass("terminal/background", 10, events),
    core_pass("terminal/glyph", 20, events, { "terminal/background" }),
    core_pass("terminal/cursor", 30, events, { "terminal/glyph" }),
  }
end

local function extension_declaration(callbacks)
  callbacks = callbacks or {}
  return {
    api_version = 1,
    extension = "fixture",
    name = callbacks.name or "observer",
    order = callbacks.order or 25,
    reads = {},
    writes = {},
    after = callbacks.after or { "terminal/glyph" },
    initialize = callbacks.initialize,
    encode = callbacks.encode or function() end,
    resize = callbacks.resize,
    shutdown = callbacks.shutdown,
  }
end

local function extension_renderer()
  return {
    frame_time = 0,
    resolve_pass_resources = function() return {} end,
    schedule_animation = function() return 0 end,
    schedule_extension_animation = function() return 0 end,
  }
end

return {
  extension_safe_mode_bypasses_all_registration = function()
    local manager = Extensions.new({ enabled = false })
    local invoked = false
    local accepted = manager:register({ function() invoked = true end }, {})
    local snapshot = manager:snapshot()
    Assert.equal(invoked, false)
    Assert.equal(#accepted, 0)
    Assert.equal(snapshot.enabled, false)
    Assert.equal(#snapshot.diagnostics, 0)
  end,
  extension_local_module_discovery_uses_a_registration_boundary = function()
    local module_name = "tests.fixture_extension"
    local previous_preload = package.preload[module_name]
    local previous_loaded = package.loaded[module_name]
    package.loaded[module_name] = nil
    package.preload[module_name] = function()
      return function(api)
        api:register(extension_declaration({ after = {} }))
      end
    end
    local manager = Extensions.new()
    local accepted = manager:register({ module_name }, {})
    package.preload[module_name] = previous_preload
    package.loaded[module_name] = previous_loaded
    Assert.equal(#accepted, 1)
    Assert.equal(accepted[1].name, "extension/fixture/observer")
    Assert.equal(#manager:snapshot().diagnostics, 0)
  end,
  extension_registration_failure_isolated_from_builtin_graph = function()
    local events = {}
    local builtins = core_passes(events)
    local manager = Extensions.new()
    local accepted = manager:register({ function(api)
      api:register(extension_declaration())
      api:register({ api_version = 2 })
    end }, builtins)
    local ordered = Registry.validate(builtins)
    local snapshot = manager:snapshot()
    Assert.equal(#accepted, 0)
    Assert.equal(#ordered, 3)
    Assert.equal(ordered[1].name, "terminal/background")
    Assert.equal(ordered[2].name, "terminal/glyph")
    Assert.equal(ordered[3].name, "terminal/cursor")
    Assert.equal(#snapshot.diagnostics, 1)
    Assert.equal(snapshot.diagnostics[1].extension, "registration-1")
    Assert.equal(snapshot.diagnostics[1].phase, "registration")
    Assert.truthy(snapshot.diagnostics[1].message:match("pass API version 2 is incompatible") ~= nil)
  end,
  extension_encode_failure_disables_the_optional_pass_and_keeps_core_available = function()
    local events = {}
    local builtins = core_passes(events)
    local manager = Extensions.new()
    local extensions = manager:register({ function(api)
      api:register(extension_declaration({
        name = "broken",
        encode = function()
          events[#events + 1] = "extension-encode"
          error("fixture encode failure")
        end,
      }))
    end }, builtins)
    local registry = Registry.new({
      on_optional_failure = function(pass, phase, message)
        manager:disable_pass(pass, phase, message)
      end,
    })
    for _, pass in ipairs(builtins) do registry:register(pass) end
    for _, pass in ipairs(extensions) do registry:register(pass) end
    local renderer = extension_renderer()
    registry:initialize(renderer)
    registry:encode(renderer, nil, nil, {})
    registry:encode(renderer, nil, nil, {})
    local snapshot = manager:snapshot()
    registry:shutdown(renderer)
    Assert.equal(
      table.concat(events, ","),
      "terminal/background-initialize,terminal/glyph-initialize,terminal/cursor-initialize,terminal/background-encode,terminal/glyph-encode,extension-encode,terminal/cursor-encode,terminal/background-encode,terminal/glyph-encode,terminal/cursor-encode,terminal/cursor-shutdown,terminal/glyph-shutdown,terminal/background-shutdown"
    )
    Assert.equal(snapshot.disabled["extension/fixture/broken"], true)
    Assert.equal(#snapshot.diagnostics, 1)
    Assert.equal(snapshot.diagnostics[1].extension, "fixture")
    Assert.equal(snapshot.diagnostics[1].pass, "extension/fixture/broken")
    Assert.equal(snapshot.diagnostics[1].phase, "encoding")
    Assert.truthy(snapshot.diagnostics[1].message:match("fixture encode failure") ~= nil)
    Assert.equal(snapshot.diagnostics[1].requested.kind, "callback-failures")
    Assert.equal(snapshot.diagnostics[1].limit.value, 1)
  end,
  extension_pass_budget_rejects_the_whole_registration_before_graph_activation = function()
    local events = {}
    local builtins = core_passes(events)
    local manager = Extensions.new({ pass_limit = 1 })
    local accepted = manager:register({ function(api)
      api:register(extension_declaration({ name = "first" }))
      api:register(extension_declaration({ name = "second" }))
    end }, builtins)
    local snapshot = manager:snapshot()
    Assert.equal(#accepted, 0)
    Assert.equal(#Registry.validate(builtins), 3)
    Assert.equal(#snapshot.diagnostics, 1)
    Assert.equal(snapshot.diagnostics[1].extension, "fixture")
    Assert.equal(snapshot.diagnostics[1].pass, "extension/fixture/second")
    Assert.equal(snapshot.diagnostics[1].requested.kind, "extension-passes")
    Assert.equal(snapshot.diagnostics[1].requested.value, 2)
    Assert.equal(snapshot.diagnostics[1].limit.value, 1)
  end,
  extension_animation_rate_rejects_over_budget_requests_without_a_redraw = function()
    local valid, invalid_message = pcall(Extensions.new, { animation_hz = 1 / 61 })
    Assert.equal(valid, false)
    Assert.truthy(tostring(invalid_message):match("between 1/60 and 60 Hz") ~= nil)
    local manager = Extensions.new({ animation_hz = 10 })
    local pass = { name = "extension/fixture/animated", extension = "fixture" }
    local scheduled = false
    local deadline, message = manager:request_animation(pass, 5, 0.05, function()
      scheduled = true
      return 5.05
    end)
    local snapshot = manager:snapshot()
    Assert.equal(deadline, nil)
    Assert.truthy(message:match("minimum delay") ~= nil)
    Assert.equal(scheduled, false)
    Assert.equal(snapshot.diagnostics[1].pass, "extension/fixture/animated")
    Assert.equal(snapshot.diagnostics[1].requested.kind, "animation-delay-seconds")
    Assert.near(snapshot.diagnostics[1].limit.value, 0.1, 0.0001)

    deadline = manager:request_animation(pass, 5, 0.1, function(reason, now, delay)
      Assert.equal(reason, "extension")
      Assert.equal(now, 5)
      Assert.near(delay, 0.1, 0.0001)
      return 5.1
    end)
    Assert.near(deadline, 5.1, 0.0001)
    Assert.near(manager:snapshot().animations[pass.name], 5.1, 0.0001)
    manager:consume_animations(5.1)
    Assert.equal(manager:snapshot().animations[pass.name], nil)
  end,
  extension_cap_state_is_bounded_and_reports_unsupported_gpu_ownership = function()
    local manager = Extensions.new({ diagnostic_limit = 2, diagnostic_message_limit = 4 })
    manager:record("fixture", nil, "registration", "abcdef")
    manager:record("fixture", nil, "registration", "second")
    manager:record("fixture", nil, "registration", "third")
    local snapshot = manager:snapshot()
    Assert.equal(#snapshot.diagnostics, 2)
    Assert.equal(snapshot.diagnostics[1].message, "seco [truncated]")
    Assert.equal(snapshot.limits.extension_buffers, 0)
    Assert.equal(snapshot.limits.extension_textures, 0)
    Assert.equal(snapshot.limits.texture_dimension, 0)
    Assert.equal(snapshot.limits.gpu_memory_accounting, "unavailable")
    Assert.equal(snapshot.limits.extension_shader_failures, 0)
  end,
}
