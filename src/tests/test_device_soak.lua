local Assert = require("tests.assert")
local Soak = require("kiwi.bench.device_soak")

return {
  device_soak_releases_each_cycle_and_contains_optional_failures = function()
    local result = Soak.run({ cycles = 4 })
    Assert.equal(result.native_releases, 8)
    Assert.equal(result.extension_disables, 2)
    Assert.equal(result.lifecycle.resize, 4)
    Assert.equal(result.lifecycle.minimize, 4)
    Assert.equal(result.lifecycle.restore, 4)
  end,
  device_soak_lifecycle_uses_bounded_resize_minimize_restore_steps = function()
    local events = {}
    local lifecycle = Soak.Lifecycle.new({
      iconify = function() events[#events + 1] = "minimize" end,
      restore = function() events[#events + 1] = "restore" end,
      set_size = function(_, width, height) events[#events + 1] = width .. "x" .. height end,
    }, { seconds = 0.7, interval = 0.2 })
    Assert.equal(lifecycle:step(3.0), false)
    Assert.equal(lifecycle:step(3.2), false)
    Assert.equal(lifecycle:step(3.41), false)
    Assert.equal(lifecycle:step(3.71), true)
    local snapshot = lifecycle:snapshot()
    Assert.equal(table.concat(events, ","), "1440x900,minimize,restore")
    Assert.equal(snapshot.lifecycle.resize, 1)
    Assert.equal(snapshot.lifecycle.minimize, 1)
    Assert.equal(snapshot.lifecycle.restore, 1)
  end,
}
