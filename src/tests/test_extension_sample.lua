local Assert = require("tests.assert")
local Sample = require("kiwi.renderer.samples.damage_observer")
local PassApi = require("kiwi.renderer.pass_api")

local function renderer(damage_cells)
  return {
    frame_time = 1,
    resolve_pass_resources = function()
      return {
        ["terminal.damage"] = { descriptor = { cells = damage_cells } },
        ["frame.timing"] = { descriptor = { time = 1 } },
      }
    end,
    schedule_extension_animation = function(_, pass, delay)
      Assert.equal(pass.name, "extension/sample/damage-observer")
      Assert.equal(delay, 0.25)
      return 1.25
    end,
  }
end

return {
  damage_observer_sample_uses_only_semantic_resources_and_schedules_once_per_damage_frame = function()
    local api = PassApi.new()
    Sample.register(api)
    Assert.equal(#api.passes, 1)
    local pass = api.passes[1]
    Assert.equal(pass.name, "extension/sample/damage-observer")
    Assert.equal(pass.reads[1], "terminal.damage")
    Assert.equal(pass.reads[2], "frame.timing")
    Assert.equal(#pass.writes, 0)
    pass:encode(renderer(2))
    Assert.equal(Sample.snapshot().frames, 1)
    Assert.equal(Sample.snapshot().scheduled, 1)
    pass:encode(renderer(0))
    Assert.equal(Sample.snapshot().frames, 2)
    Assert.equal(Sample.snapshot().scheduled, 1)
    pass:shutdown(renderer(0))
    Assert.equal(Sample.snapshot().frames, 0)
  end,
}
