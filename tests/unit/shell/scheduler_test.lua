local assertions = require("support.assertions")
local Errors = require("runtime.errors")
local Scheduler = require("shell.scheduler")

local function scheduler(limits)
  return assert(Scheduler.new(limits))
end

local function assert_error(call, reason)
  local result, call_error = call()
  assertions.falsy(result)
  assertions.equal("sandbox_command_error", call_error.kind)
  assertions.equal(reason, call_error.detail.reason)
end

return {
  {
    name = "sandbox scheduler advances only explicit logical time and orders due jobs deterministically",
    run = function()
      local value = scheduler()
      local trace = {}
      assert(value:schedule(5, function(context)
        trace[#trace + 1] = "late:" .. context.execution_sequence
      end))
      local first = assert(value:schedule(2, function(context)
        trace[#trace + 1] = "first:" .. context.execution_sequence
      end))
      local second = assert(value:schedule(2, function(context)
        trace[#trace + 1] = "second:" .. context.execution_sequence
      end))
      assertions.equal(2, first)
      assertions.equal(3, second)
      assertions.equal(0, assert(value:advance(1)).executed)
      assertions.equal(1, value:status().logical_time_us)
      assertions.equal(2, assert(value:advance(1)).executed)
      assertions.equal("first:1|second:2", table.concat(trace, "|"))
      assertions.equal(1, assert(value:advance(3)).executed)
      assertions.equal("first:1|second:2|late:3", table.concat(trace, "|"))
    end,
  },
  {
    name = "sandbox scheduler drains bounded zero-delay work without reentrant advance",
    run = function()
      local value = scheduler({ max_callbacks_per_advance = 2 })
      local trace = {}
      assert(value:schedule(0, function(context)
        trace[#trace + 1] = "one"
        assert_error(function()
          return value:advance(0)
        end, "scheduler_reentrant")
        assert(value:schedule(0, function()
          trace[#trace + 1] = "three"
        end))
      end))
      assert(value:schedule(0, function()
        trace[#trace + 1] = "two"
      end))
      local first = assert(value:advance(0))
      assertions.equal("one|two", table.concat(trace, "|"))
      assertions.truthy(first.callback_budget_exhausted)
      local second = assert(value:advance(0))
      assertions.equal(1, second.executed)
      assertions.equal("one|two|three", table.concat(trace, "|"))
    end,
  },
  {
    name = "sandbox scheduler validates limits cancellation failures and cleanup without state mutation",
    run = function()
      local value = scheduler({
        max_active_jobs = 1,
        max_advance_us = 4,
        max_delay_us = 4,
        max_logical_time_us = 8,
      })
      assert_error(function()
        return value:advance(-1)
      end, "invalid_delta_us")
      assert_error(function()
        return value:advance(5)
      end, "advance_too_large")
      assert_error(function()
        return value:schedule(5, function() end)
      end, "delay_too_large")
      local cancelled = 0
      local first = assert(value:schedule(4, function() end, {
        on_finish = function(_, state)
          if state == "cancelled" then
            cancelled = cancelled + 1
          end
        end,
      }))
      assert_error(function()
        return value:schedule(1, function() end)
      end, "scheduler_full")
      assertions.truthy(assert(value:is_pending(first)))
      assertions.truthy(assert(value:cancel(first)).cancelled)
      assertions.falsy(assert(value:cancel(first)).cancelled)
      assertions.equal(1, cancelled)
      assert_error(function()
        return value:cancel("invalid")
      end, "unknown_job")
      local failed = assert(value:schedule(0, function()
        return nil, Errors.new("sandbox_command_error", "failed", { reason = "custom" })
      end))
      local result = assert(value:advance(0))
      assertions.equal(failed, result.failures[1].job_id)
      assertions.equal("callback_failure", result.failures[1].error.detail.reason)
      assertions.equal("custom", result.failures[1].error.detail.cause_reason)
      assertions.truthy(value:destroy())
      assertions.equal(0, value:status().active_jobs)
      assert_error(function()
        return value:schedule(0, function() end)
      end, "scheduling_closed")
    end,
  },
}
