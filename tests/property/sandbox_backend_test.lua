local assertions = require("support.assertions")
local Builtins = require("shell.builtins")
local Registry = require("shell.registry")
local Sandbox = require("backend.sandbox")

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

local function backend()
  local registry = assert(Registry.new())
  assert(Builtins.register(registry))
  assert(registry:register("later", {
    capabilities = { "jobs.schedule" },
    run = function(context, argv)
      return context.jobs:schedule(0, function(job)
        assert(job.writer:emit(argv[2]))
      end)
    end,
    summary = "Emit later",
  }))
  local value = assert(Sandbox.new(registry, {
    session = { granted_capabilities = { "jobs.schedule", "vfs.read", "vfs.write" } },
  }))
  assert(value:start())
  return value
end

return {
  {
    name = "property sandbox backend preserves generated command output and VFS isolation",
    run = function()
      for iteration = 1, 32 do
        local sandbox = backend()
        local files = {}
        for _ = 1, 32 do
          local name = string.char(97 + math.random(0, 3))
          local data = string.char(65 + math.random(0, 25)) .. tostring(math.random(0, 9))
          local operation = math.random(1, 3)
          local expected = ""
          if operation == 1 then
            assert(sandbox:send_input("write /" .. name .. " " .. data))
            files[name] = data
          elseif operation == 2 then
            assert(sandbox:send_input("later " .. data))
            expected = data
          elseif files[name] then
            assert(sandbox:send_input("cat /" .. name))
            expected = files[name]
          else
            local outcome = assert(sandbox:send_input("cat /" .. name))
            assertions.truthy(outcome.failed)
          end
          assertions.equal(
            expected,
            event_bytes(assert(sandbox:poll(0))),
            "iteration " .. iteration
          )
          assertions.truthy(
            sandbox:status().active_invocations <= 32,
            "bounds iteration " .. iteration
          )
        end
        assert(sandbox:stop())
      end
    end,
  },
}
