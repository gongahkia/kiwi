local assertions = require("support.assertions")
local Backend = require("backend.interface")
local Builtins = require("shell.builtins")
local Registry = require("shell.registry")
local Sandbox = require("backend.sandbox")

local function registry()
  local value = assert(Registry.new())
  assert(Builtins.register(value))
  return value
end

local function backend(value, configuration)
  configuration = configuration or {}
  configuration.session = configuration.session or {}
  configuration.session.granted_capabilities = configuration.session.granted_capabilities
    or { "jobs.schedule", "vfs.chdir", "vfs.read", "vfs.write" }
  local result = assert(Sandbox.new(value, configuration))
  assert(result:start())
  return result
end

local function event_bytes(events)
  local chunks = {}
  for _, event in ipairs(events) do
    if event.kind == "output" then
      assertions.equal(0, event.delta_us)
      chunks[#chunks + 1] = event.data
    end
  end
  return table.concat(chunks)
end

return {
  {
    name = "sandbox backend dispatches built-ins through isolated session VFS and output polling",
    run = function()
      local first = backend(registry())
      assertions.equal(first, assert(Backend.validate(first)))
      assert(first:send_input('write /note "first value"'))
      assertions.equal(0, #assert(first:poll(0)))
      assert(first:send_input("cat /note"))
      assertions.equal("first value", event_bytes(assert(first:poll(0))))
      assertions.equal(0, first:history():length() - 2)
      assert(first:send_input("mkdir /work"))
      assert(first:send_input("cd /work"))
      assert(first:send_input("pwd"))
      assertions.equal("/work\n", event_bytes(assert(first:poll(0))))

      local second = backend(registry())
      local missing = assert(second:send_input("cat /note"))
      assertions.truthy(missing.failed)
      assertions.equal("not_found", missing.failure.detail.reason)
      assertions.equal(1, second:history():length())
      assert(first:stop())
      assert(second:stop())
    end,
  },
  {
    name = "sandbox backend advances scheduled callbacks only through deterministic poll time",
    run = function()
      local value = registry()
      assert(value:register("later", {
        capabilities = { "jobs.schedule" },
        run = function(context)
          return context.jobs:schedule(3, function(job)
            assert(job.writer:emit("later"))
          end)
        end,
        summary = "Schedule output",
      }))
      local sandbox = backend(value)
      local outcome = assert(sandbox:send_input("later"))
      assertions.equal(1, outcome.result)
      assertions.equal(1, sandbox:status().active_invocations)
      assertions.equal("", event_bytes(assert(sandbox:poll(2))))
      assertions.equal("later", event_bytes(assert(sandbox:poll(1))))
      assertions.equal(0, sandbox:status().active_invocations)
      assertions.equal(3, sandbox:status().session.scheduler.logical_time_us)
      assert(sandbox:stop())
    end,
  },
  {
    name = "sandbox backend bounds active invocations and isolates dispatch failures from events",
    run = function()
      local value = registry()
      local calls = 0
      assert(value:register("show", {
        run = function(_, _, writer)
          calls = calls + 1
          assert(writer:emit("queued"))
        end,
        summary = "Show output",
      }))
      local sandbox = backend(value, { max_active_invocations = 1 })
      assert(sandbox:send_input("show"))
      local full, full_error = sandbox:send_input("show")
      assertions.falsy(full)
      assertions.equal("resource_limit", full_error.detail.reason)
      assertions.equal(1, calls)
      assertions.equal("queued", event_bytes(assert(sandbox:poll(0))))
      assert(sandbox:send_input("show"))
      assertions.equal("queued", event_bytes(assert(sandbox:poll(0))))

      local malformed, malformed_error = sandbox:send_input("show '")
      assertions.falsy(malformed)
      assertions.equal("unterminated_single_quote", malformed_error.detail.reason)
      local unknown, unknown_error = sandbox:send_input("missing")
      assertions.falsy(unknown)
      assertions.equal("sandbox_command_error", unknown_error.kind)
      assertions.equal(0, #assert(sandbox:poll(0)))
      assertions.equal(3, sandbox:history():length())
      assert(sandbox:stop())
    end,
  },
  {
    name = "sandbox backend exposes bounded completion resize and stop without process authority",
    run = function()
      local sandbox = backend(registry(), { max_events_per_poll = 1 })
      local completion = assert(sandbox:complete("c", 1))
      assertions.equal("cat", completion.candidates[1].display)
      assert(sandbox:resize(100, 30, 800, 480))
      local queued, queue_error = sandbox:resize(80, 24, 640, 384)
      assertions.falsy(queued)
      assertions.equal("resource_limit", queue_error.detail.reason)
      local first = assert(sandbox:poll(0))
      assertions.equal(1, #first)
      assertions.equal("resize", first[1].kind)
      assertions.equal(100, first[1].columns)
      assert(sandbox:resize(80, 24, 640, 384))
      local second = assert(sandbox:poll(0))
      assertions.equal(1, #second)
      assertions.equal(80, second[1].columns)
      assertions.truthy(sandbox:capabilities().sandbox_commands)
      assertions.falsy(sandbox:capabilities().seek)
      assert(sandbox:stop("test"))
      assert(sandbox:stop("test"))
      local events, stopped_error = sandbox:poll(0)
      assertions.falsy(events)
      assertions.equal("backend_exited", stopped_error.kind)
    end,
  },
}
