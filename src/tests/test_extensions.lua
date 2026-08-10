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
  end,
}
