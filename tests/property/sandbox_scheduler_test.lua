local assertions = require("support.assertions")
local Scheduler = require("shell.scheduler")

return {
  {
    name = "property generated sandbox schedules preserve due order and active-job bounds",
    run = function()
      for iteration = 1, 128 do
        local scheduler = assert(Scheduler.new({
          max_active_jobs = 16,
          max_advance_us = 8,
          max_callbacks_per_advance = 4,
          max_delay_us = 16,
          max_logical_time_us = 1024,
        }))
        local trace = {}
        for step = 1, 64 do
          if math.random(1, 2) == 1 then
            local expected_due = scheduler:status().logical_time_us + math.random(0, 8)
            local id = scheduler:schedule(
              expected_due - scheduler:status().logical_time_us,
              function(context)
                trace[#trace + 1] = { due = context.due_us, id = context.job_id }
              end
            )
            if not id then
              assertions.equal(16, scheduler:status().active_jobs, "full iteration " .. iteration)
            end
          else
            assert(scheduler:advance(math.random(0, 8)))
          end
          assertions.truthy(scheduler:status().active_jobs <= 16, "bounds iteration " .. iteration)
        end
        while scheduler:status().active_jobs > 0 do
          assert(scheduler:advance(8))
        end
        for index = 2, #trace do
          assertions.truthy(
            trace[index - 1].due <= trace[index].due,
            "order iteration " .. iteration
          )
          if trace[index - 1].due == trace[index].due then
            assertions.truthy(trace[index - 1].id < trace[index].id, "tie iteration " .. iteration)
          end
        end
      end
    end,
  },
}
