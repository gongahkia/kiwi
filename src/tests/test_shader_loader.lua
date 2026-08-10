local Assert = require("tests.assert")
local Loader = require("kiwi.renderer.shader_loader")

local function definition()
  return {
    id = "test/module",
    pass = "test/pass",
    path = "fixtures/test.wgsl",
  }
end

local function expect_error(callback)
  local ok, message = pcall(callback)
  Assert.equal(ok, false)
  return tostring(message)
end

return {
  shader_loader_tracks_stable_module_and_pass_identity = function()
    local loader = Loader.new({
      read_source = function(path)
        Assert.equal(path, "fixtures/test.wgsl")
        return "@vertex fn main() {}"
      end,
      compile = function(item, source)
        Assert.equal(item.id, "test/module")
        Assert.equal(item.pass, "test/pass")
        Assert.equal(source, "@vertex fn main() {}")
        return { handle = {}, diagnostics = "warning line=1 column=1: test warning" }
      end,
    })
    local module = loader:load(definition())
    Assert.equal(module.id, "test/module")
    Assert.equal(module.pass, "test/pass")
    Assert.equal(module.path, "fixtures/test.wgsl")
    Assert.equal(module.source_bytes, 20)
    Assert.truthy(module.handle ~= nil)
    Assert.truthy(module.diagnostics:match("warning") ~= nil)
  end,
  shader_loader_reports_missing_sources_with_module_context = function()
    local loader = Loader.new({
      read_source = function() return nil, "no such file" end,
      compile = function() error("compile must not run") end,
    })
    local message = expect_error(function() loader:load(definition()) end)
    Assert.truthy(message:match("shader module test/module for pass test/pass from fixtures/test.wgsl") ~= nil)
    Assert.truthy(message:match("could not read source: no such file") ~= nil)
  end,
  shader_loader_reports_invalid_sources_without_retaining_the_module = function()
    local released = 0
    local loader = Loader.new({
      read_source = function() return "@vertex fn broken(" end,
      compile = function()
        return {
          handle = {},
          diagnostics = "error line=1 column=19 offset=18 length=1: expected type",
          release = function() released = released + 1 end,
        }
      end,
    })
    local message = expect_error(function() loader:load(definition()) end)
    Assert.equal(released, 1)
    Assert.truthy(message:match("compilation failed: error line=1 column=19") ~= nil)
  end,
  shader_loader_bounds_source_size_before_compilation = function()
    local loader = Loader.new({
      max_source_bytes = 3,
      read_source = function() return "four" end,
      compile = function() error("compile must not run") end,
    })
    local message = expect_error(function() loader:load(definition()) end)
    Assert.truthy(message:match("source exceeds 3 byte limit") ~= nil)
  end,
}
