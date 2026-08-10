local Assert = require("tests.assert")
local Recovery = require("kiwi.gpu.recovery")

return {
  gpu_recovery_retries_one_device_loss_with_adapter_and_pass_context = function()
    local recovery = Recovery.new({ history_limit = 2, max_device_retries = 1 })
    local item = recovery:decide("native GPU error: wgpu device lost 1: reset", {
      adapter_info = { backend_name = "Vulkan", vendor = "Mesa", device = "Iris Xe" },
    }, {
      last = { name = "terminal/glyph", phase = "encode" },
    })
    local snapshot = recovery:snapshot()
    Assert.equal(item.action, "retry-device")
    Assert.equal(item.pass.name, "terminal/glyph")
    Assert.equal(item.adapter.backend, "Vulkan")
    Assert.equal(snapshot.device_retries, 1)
    Assert.equal(snapshot.history[1].message, "native GPU error: wgpu device lost 1: reset")
    Assert.truthy(Recovery.format(item, snapshot.limits.device_retries):match("pass=terminal/glyph") ~= nil)
  end,
  gpu_recovery_exits_after_the_single_retry_and_for_other_native_errors = function()
    local recovery = Recovery.new({ max_device_retries = 1 })
    Assert.equal(recovery:decide("native GPU error: simulated device loss").action, "retry-device")
    Assert.equal(recovery:decide("native GPU error: wgpu device lost 2: reset").action, "exit")
    Assert.equal(Recovery.new():decide("native GPU error: wgpu error 1: validation").action, "exit")
  end,
  gpu_recovery_reconfigures_surface_errors_without_consuming_device_retry = function()
    local recovery = Recovery.new()
    Assert.equal(recovery:decide("surface acquire status 2").action, "retry-surface")
    Assert.equal(recovery:snapshot().device_retries, 0)
    Assert.equal(recovery:decide("zero-sized drawable").action, "wait")
  end,
  gpu_recovery_bounds_history = function()
    local recovery = Recovery.new({ history_limit = 1 })
    recovery:decide("surface present status 2")
    recovery:decide("native GPU error: validation")
    local snapshot = recovery:snapshot()
    Assert.equal(#snapshot.history, 1)
    Assert.equal(snapshot.history[1].kind, "fatal-native-error")
  end,
}
