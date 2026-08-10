local Assert = require("tests.assert")
local Api = require("kiwi.renderer.pass_api")
local Registry = require("kiwi.renderer.pass_registry")

local function expect_error(callback)
  local ok, message = pcall(callback)
  Assert.equal(ok, false)
  return tostring(message)
end

local function renderer()
  return {
    resolve_pass_resources = function(_, pass)
      local resources = {}
      for _, name in ipairs(pass.reads) do resources[name] = { name = name, descriptor = { access = "read" } } end
      for _, name in ipairs(pass.writes) do resources[name] = { name = name, descriptor = { access = "write" } } end
      return resources
    end,
  }
end

local function core_pass(events)
  return {
    name = "terminal/cursor",
    order = 30,
    reads = {},
    writes = {},
    after = {},
    initialize = function() events[#events + 1] = "core-initialize" end,
    encode = function() events[#events + 1] = "core-encode" end,
    shutdown = function() events[#events + 1] = "core-shutdown" end,
  }
end

return {
  versioned_pass_api_registers_semantic_callbacks_without_native_renderer_access = function()
    local events = {}
    local api = Api.new()
    api:register_extensions({
      function(registration)
        registration:register({
          api_version = Api.version,
          extension = "example",
          name = "frame_observer",
          order = 40,
          reads = { "frame.timing" },
          writes = {},
          after = { "terminal/cursor" },
          initialize = function(context)
            Assert.equal(context.api_version, 1)
            Assert.equal(context.pass.id, "extension/example/frame_observer")
            Assert.equal(context.renderer, nil)
            Assert.equal(context.encoder, nil)
            Assert.equal(context.resources["frame.timing"].descriptor.access, "read")
            events[#events + 1] = "extension-initialize"
          end,
          encode = function(context)
            Assert.equal(context.phase, "encode")
            Assert.equal(context.resources["frame.timing"].name, "frame.timing")
            events[#events + 1] = "extension-encode"
          end,
          resize = function(context)
            Assert.equal(context.resize.previous.columns, 80)
            Assert.equal(context.resize.current.columns, 120)
            events[#events + 1] = "extension-resize"
          end,
          shutdown = function(context)
            Assert.equal(context.phase, "shutdown")
            events[#events + 1] = "extension-shutdown"
          end,
        })
      end,
    })
    local registry = Registry.new()
    registry:register(core_pass(events))
    for _, pass in ipairs(api.passes) do registry:register(pass) end
    local owner = renderer()
    registry:initialize(owner)
    registry:encode(owner, nil, nil, {})
    registry:resize(owner, { columns = 80 }, { columns = 120 })
    registry:shutdown(owner)
    Assert.equal(
      table.concat(events, ","),
      "core-initialize,extension-initialize,core-encode,extension-encode,extension-resize,extension-shutdown,core-shutdown"
    )
  end,
  versioned_pass_api_rejects_incompatible_versions_and_incomplete_declarations = function()
    local api = Api.new()
    local version_message = expect_error(function()
      api:register({ api_version = 2 })
    end)
    Assert.truthy(version_message:match("pass API version 2 is incompatible; supported version is 1") ~= nil)
    local declaration_message = expect_error(function()
      api:register({
        api_version = Api.version,
        extension = "example",
        name = "missing_encode",
        order = 40,
        reads = {},
        writes = {},
        after = {},
      })
    end)
    Assert.truthy(declaration_message:match("encode callback must be a function") ~= nil)
  end,
  versioned_pass_api_rejects_undeclared_semantic_resource_access = function()
    local api = Api.new()
    local message = expect_error(function()
      api:register({
        api_version = Api.version,
        extension = "example",
        name = "invalid_resource",
        order = 40,
        reads = { "surface.color" },
        writes = {},
        after = {},
        encode = function() end,
      })
    end)
    Assert.truthy(message:match("cannot read resource surface%.color") ~= nil)
  end,
}
