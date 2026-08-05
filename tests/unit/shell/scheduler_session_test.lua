local assertions = require("support.assertions")
local Registry = require("shell.registry")
local Session = require("shell.session")

local function session(registry, configuration)
  configuration = configuration or {}
  configuration.granted_capabilities = configuration.granted_capabilities or { "jobs.schedule" }
  return assert(Session.new(registry, configuration))
end

local function bytes(invocation)
  local chunks = {}
  while invocation:status().queued_chunks > 0 do
    local result = assert(invocation:poll())
    for _, event in ipairs(result.events) do
      assertions.equal(0, event.delta_us)
      chunks[#chunks + 1] = event.data
    end
  end
  return table.concat(chunks)
end

return {
  {
    name = "sandbox sessions retain scheduled command work until callbacks and output drain",
    run = function()
      local registry = assert(Registry.new())
      local retained_jobs
      assert(registry:register("later", {
        capabilities = { "jobs.schedule" },
        run = function(context, _, writer)
          retained_jobs = context.jobs
          return context.jobs:schedule(5, function(job)
            assertions.equal(1, job.job_id)
            assertions.equal(5, job.due_us)
            assertions.equal(5, job.logical_time_us)
            assert(job.writer:emit("later"))
          end)
        end,
        summary = "Schedule output",
      }))
      local sandbox = session(registry)
      local outcome = assert(sandbox:dispatch("later"))
      assertions.equal(1, outcome.result)
      assertions.equal("running", outcome.invocation:status().execution_state)
      assertions.equal(1, outcome.invocation:status().pending_work)
      local pending, pending_error = retained_jobs:is_pending(1)
      assertions.falsy(pending)
      assertions.equal("scheduling_closed", pending_error.detail.reason)
      local advance = assert(sandbox:advance(4))
      assertions.equal(0, advance.executed)
      assertions.equal(0, outcome.invocation:status().queued_bytes)
      advance = assert(sandbox:advance(1))
      assertions.equal(1, advance.executed)
      assertions.equal("finished_with_output", outcome.invocation:status().state)
      assertions.equal("later", bytes(outcome.invocation))
      assertions.truthy(outcome.invocation:status().settled)
      local scheduled, closed_error = retained_jobs:schedule(0, function() end)
      assertions.falsy(scheduled)
      assertions.equal("scheduling_closed", closed_error.detail.reason)
    end,
  },
  {
    name = "sandbox session jobs keep due insertion order and isolate callback failure cancellation",
    run = function()
      local registry = assert(Registry.new())
      assert(registry:register("order", {
        capabilities = { "jobs.schedule" },
        run = function(context)
          assert(context.jobs:schedule(1, function(job)
            assert(job.writer:emit("a"))
            assert(job.jobs:schedule(0, function(next_job)
              assert(next_job.writer:emit("c"))
            end))
          end))
          assert(context.jobs:schedule(1, function(job)
            assert(job.writer:emit("b"))
          end))
        end,
        summary = "Order jobs",
      }))
      assert(registry:register("failjob", {
        capabilities = { "jobs.schedule" },
        run = function(context, _, writer)
          assert(writer:emit("before"))
          assert(context.jobs:schedule(0, function(job)
            assert(job.writer:emit("failed"))
            error("expected")
          end))
          assert(context.jobs:schedule(0, function(job)
            assert(job.writer:emit("never"))
          end))
        end,
        summary = "Fail job",
      }))
      local sandbox = session(registry)
      local ordered = assert(sandbox:dispatch("order"))
      assert(sandbox:advance(1))
      assertions.equal("abc", bytes(ordered.invocation))
      assertions.truthy(ordered.invocation:status().settled)

      local failed = assert(sandbox:dispatch("failjob"))
      local advance = assert(sandbox:advance(0))
      assertions.equal(1, #advance.failures)
      assertions.equal("callback_failure", advance.failures[1].error.detail.reason)
      assertions.equal("beforefailed", bytes(failed.invocation))
      assertions.equal("callback_failure", failed.invocation:status().failure.detail.reason)
      assertions.equal(0, sandbox:status().scheduler.active_jobs)
    end,
  },
  {
    name = "sandbox session scheduling capabilities and cancellation do not leak between invocations",
    run = function()
      local registry = assert(Registry.new())
      local invoked = 0
      assert(registry:register("wait", {
        capabilities = { "jobs.schedule" },
        run = function(context)
          invoked = invoked + 1
          assert(context.jobs:schedule(1, function(job)
            assert(job.writer:emit("late"))
          end))
        end,
        summary = "Wait",
      }))
      local denied = assert(Session.new(registry))
      local outcome, denied_error = denied:dispatch("wait")
      assertions.falsy(outcome)
      assertions.equal("capability_denied", denied_error.detail.reason)
      assertions.equal(0, invoked)
      assertions.equal("wait", assert(denied:history():get(1)))

      local sandbox = session(registry)
      local pending = assert(sandbox:dispatch("wait"))
      assert(pending.invocation:cancel())
      assertions.equal("cancelled", pending.invocation:status().execution_state)
      assertions.equal(0, sandbox:status().scheduler.active_jobs)
      local advance = assert(sandbox:advance(1))
      assertions.equal(0, advance.executed)
      assertions.equal(1, invoked)
      assert(sandbox:destroy())
      assertions.equal(0, sandbox:status().scheduler.active_jobs)
    end,
  },
}
