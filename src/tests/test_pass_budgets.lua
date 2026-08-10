local Assert = require("tests.assert")
local Budgets = require("kiwi.renderer.pass_budgets")

local function cpu(frame, name, prepare_ms, encode_ms)
  return { enabled = true, frame = frame, samples = { { name = name, prepare_ms = prepare_ms, encode_ms = encode_ms } } }
end

local function gpu(frame, name, ticks)
  return { enabled = true, status = "supported", timed_passes = { name }, samples = { { frame = frame, name = name, gpu_ticks = ticks } } }
end

return {
  pass_budgets_compare_bounded_cpu_gpu_and_cadence_windows = function()
    local manager = Budgets.new({ enabled = true, warning_limit = 2 })
    local name = "extension/example/observer"
    manager:register({ {
      name = name,
      budget = { cpu_ms = 2, gpu_ticks = 100, allocation_bytes = 64, cadence_hz = 5, window = 2 },
    } })
    manager:observe(cpu(1, name, 1, 2), gpu(1, name, 90), 1)
    manager:observe(cpu(2, name, 0.5, 0.5), gpu(2, name, 150), 1.25)
    local snapshot = manager:snapshot()
    local pass = snapshot.passes[1]
    Assert.equal(pass.name, name)
    Assert.equal(pass.status, "over-budget")
    Assert.equal(pass.dimensions.cpu_ms.status, "within-budget")
    Assert.near(pass.dimensions.cpu_ms.average, 2, 0.0001)
    Assert.equal(pass.dimensions.cpu_ms.sample_count, 2)
    Assert.equal(pass.dimensions.gpu_ticks.status, "over-budget")
    Assert.near(pass.dimensions.gpu_ticks.average, 120, 0.0001)
    Assert.equal(pass.dimensions.cadence_hz.status, "within-budget")
    Assert.near(pass.dimensions.cadence_hz.latest, 4, 0.0001)
    Assert.equal(pass.dimensions.allocation_bytes.status, "unavailable")
    Assert.equal(#snapshot.warnings, 2)
    Assert.equal(snapshot.warnings[2].pass, name)
    Assert.equal(snapshot.warnings[2].dimension, "gpu_ticks")
    Assert.equal(snapshot.warnings[2].window, 2)
  end,
  pass_budgets_keep_cpu_accounting_when_gpu_timing_is_unavailable = function()
    local manager = Budgets.new({ enabled = true })
    local name = "extension/example/cpu"
    manager:register({ { name = name, budget = { cpu_ms = 1, gpu_ticks = 10, window = 1 } } })
    manager:observe(cpu(1, name, 0.75, 0.75), { enabled = false, status = "adapter does not expose timestamp-query", samples = {} }, 1)
    local pass = manager:snapshot().passes[1]
    Assert.equal(pass.status, "over-budget")
    Assert.equal(pass.dimensions.cpu_ms.status, "over-budget")
    Assert.equal(pass.dimensions.gpu_ticks.status, "unavailable")
    Assert.equal(pass.dimensions.gpu_ticks.reason, "adapter does not expose timestamp-query")
  end,
  pass_budgets_bound_windows_and_reset_state = function()
    local manager = Budgets.new({ enabled = true, warning_limit = 1 })
    local name = "extension/example/reset"
    manager:register({ { name = name, budget = { cpu_ms = 1, window = 1 } } })
    manager:observe(cpu(1, name, 2, 0), { enabled = false, status = "disabled", samples = {} }, 1)
    manager:observe(cpu(2, name, 3, 0), { enabled = false, status = "disabled", samples = {} }, 2)
    local snapshot = manager:snapshot()
    Assert.equal(snapshot.passes[1].dimensions.cpu_ms.sample_count, 1)
    Assert.equal(snapshot.passes[1].dimensions.cpu_ms.latest, 3)
    Assert.equal(#snapshot.warnings, 1)
    Assert.equal(snapshot.warnings[1].frame, 2)
    manager:reset()
    snapshot = manager:snapshot()
    Assert.equal(snapshot.passes[1].dimensions.cpu_ms.status, "pending")
    Assert.equal(snapshot.passes[1].dimensions.cpu_ms.sample_count, 0)
    Assert.equal(#snapshot.warnings, 0)
  end,
  pass_budgets_reject_unbounded_configuration = function()
    local valid, message = pcall(Budgets.copy, { cpu_ms = 1, window = 121 }, "fixture budget")
    Assert.equal(valid, false)
    Assert.truthy(tostring(message):match("no greater than 120") ~= nil)
    valid, message = pcall(Budgets.new, { warning_limit = 65 })
    Assert.equal(valid, false)
    Assert.truthy(tostring(message):match("no greater than 64") ~= nil)
  end,
}
