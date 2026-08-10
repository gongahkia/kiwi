local work = 0

return function(api)
  api:register({
    api_version = 1,
    extension = "fixture",
    name = "budget_observer",
    order = 40,
    reads = { "frame.timing" },
    writes = {},
    after = { "terminal/cursor" },
    budget = { cpu_ms = 0.001, gpu_ticks = 1, allocation_bytes = 0, cadence_hz = 1, window = 2 },
    initialize = function(context)
      assert(context.pass.budget.cpu_ms == 0.001)
      assert(context.budget.status == "pending")
    end,
    encode = function()
      for index = 1, 200000 do work = work + index end
    end,
  })
end
