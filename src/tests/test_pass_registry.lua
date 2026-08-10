local Assert = require("tests.assert")
local Registry = require("kiwi.renderer.pass_registry")

local function expect_error(callback)
  local ok, message = pcall(callback)
  Assert.equal(ok, false)
  Assert.truthy(tostring(message):match("render pass registry") ~= nil)
end

local function pass(name, order, events, options)
  options = options or {}
  return {
    name = name,
    order = order,
    reads = {},
    writes = {},
    after = options.after or {},
    initialize = function()
      events[#events + 1] = name .. "-initialize"
      if options.initialize_error then error(options.initialize_error) end
    end,
    encode = function()
      events[#events + 1] = name .. "-encode"
      if options.encode_error then error(options.encode_error) end
    end,
    shutdown = function()
      events[#events + 1] = name .. "-shutdown"
    end,
    resize = options.resize and function()
      events[#events + 1] = name .. "-resize"
    end or nil,
  }
end

return {
  render_pass_registry_orders_lifecycle_by_key_then_name = function()
    local registry = Registry.new()
    local events = {}
    registry:register(pass("zeta", 20, events))
    registry:register(pass("background", 10, events))
    registry:register(pass("alpha", 20, events))
    registry:initialize({})
    registry:encode({}, nil, nil, {})
    registry:shutdown({})
    Assert.equal(
      table.concat(events, ","),
      "background-initialize,alpha-initialize,zeta-initialize,background-encode,alpha-encode,zeta-encode,zeta-shutdown,alpha-shutdown,background-shutdown"
    )
  end,
  render_pass_registry_rejects_duplicates_and_invalid_transitions = function()
    local registry = Registry.new()
    local events = {}
    registry:register(pass("glyph", 20, events))
    expect_error(function() registry:register(pass("glyph", 30, events)) end)
    expect_error(function() registry:encode({}, nil, nil, {}) end)
    registry:initialize({})
    expect_error(function() registry:register(pass("cursor", 30, events)) end)
    expect_error(function() registry:initialize({}) end)
    registry:shutdown({})
  end,
  render_pass_registry_cleans_up_initialized_passes_after_failure = function()
    local registry = Registry.new()
    local events = {}
    registry:register(pass("first", 10, events))
    registry:register(pass("broken", 20, events, { initialize_error = "expected initialization failure" }))
    expect_error(function() registry:initialize({}) end)
    registry:shutdown({})
    Assert.equal(table.concat(events, ","), "first-initialize,broken-initialize,broken-shutdown,first-shutdown")
  end,
  render_pass_registry_topologically_orders_explicit_dependencies = function()
    local registry = Registry.new()
    local events = {}
    registry:register(pass("cursor", 30, events, { after = { "glyph" } }))
    registry:register(pass("overlay", 30, events, { after = { "background" } }))
    registry:register(pass("glyph", 20, events, { after = { "background" } }))
    registry:register(pass("background", 10, events))
    registry:initialize({})
    registry:encode({}, nil, nil, {})
    Assert.equal(table.concat(events, ","), "background-initialize,glyph-initialize,overlay-initialize,cursor-initialize,background-encode,glyph-encode,overlay-encode,cursor-encode")
    Assert.equal(#registry.parallel_groups, 3)
    Assert.equal(#registry.parallel_groups[2], 2)
    Assert.equal(registry.parallel_groups[2][1].name, "glyph")
    Assert.equal(registry.parallel_groups[2][2].name, "overlay")
    registry:shutdown({})
  end,
  render_pass_registry_rejects_missing_dependencies_and_cycle_paths = function()
    local events = {}
    local missing = Registry.new()
    missing:register(pass("glyph", 20, events, { after = { "background" } }))
    expect_error(function() missing:initialize({}) end)

    local cycle = Registry.new()
    cycle:register(pass("alpha", 10, events, { after = { "gamma" } }))
    cycle:register(pass("beta", 20, events, { after = { "alpha" } }))
    cycle:register(pass("gamma", 30, events, { after = { "beta" } }))
    local ok, message = pcall(function() cycle:initialize({}) end)
    Assert.equal(ok, false)
    Assert.truthy(tostring(message):match("alpha %-%> gamma %-%> beta %-%> alpha") ~= nil)
  end,
  render_pass_registry_dispatches_resize_in_deterministic_pass_order = function()
    local registry = Registry.new()
    local events = {}
    registry:register(pass("glyph", 20, events, { resize = true, after = { "background" } }))
    registry:register(pass("background", 10, events, { resize = true }))
    registry:initialize({})
    registry:resize({}, { columns = 80 }, { columns = 120 })
    registry:shutdown({})
    Assert.equal(table.concat(events, ","), "background-initialize,glyph-initialize,background-resize,glyph-resize,glyph-shutdown,background-shutdown")
  end,
}
