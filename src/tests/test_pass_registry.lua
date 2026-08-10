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
}
