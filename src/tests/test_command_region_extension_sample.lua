local Assert = require("tests.assert")
local PassApi = require("kiwi.renderer.pass_api")
local Sample = require("kiwi.renderer.samples.command_region_observer")

local function renderer(boundaries)
  return {
    resolve_pass_resources = function()
      return {
        ["terminal.command_regions"] = { descriptor = { boundary_count = boundaries } },
        ["frame.timing"] = { descriptor = { time = 1 } },
      }
    end,
  }
end

return {
  command_region_observer_uses_the_declared_typed_resource = function()
    local api = PassApi.new()
    Sample.register(api)
    local pass = api.passes[1]
    Assert.equal(pass.name, "extension/sample/command-region-observer")
    Assert.equal(pass.reads[1], "terminal.command_regions")
    Assert.equal(pass.reads[2], "frame.timing")
    Assert.equal(#pass.writes, 0)
    pass:encode(renderer(3))
    Assert.equal(Sample.snapshot().boundaries, 3)
    pass:shutdown(renderer(0))
    Assert.equal(Sample.snapshot().frames, 0)
  end,
}
