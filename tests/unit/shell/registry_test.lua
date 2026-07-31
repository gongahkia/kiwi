local assertions = require("support.assertions")
local Registry = require("shell.registry")

local function definition(overrides)
  local value = {
    capabilities = { "domain_events" },
    complete = function() end,
    run = function() end,
    summary = "Unlock a game object",
  }
  for name, field in pairs(overrides or {}) do
    value[name] = field
  end
  return value
end

return {
  {
    name = "sandbox registry stores bounded immutable command definitions",
    run = function()
      local registry = assert(Registry.new({ max_commands = 2 }))
      local command_definition = definition()
      assert(registry:register("unlock", command_definition))
      command_definition.capabilities[1] = "vfs.write"
      command_definition.summary = "mutated"

      local command = assert(registry:command("unlock"))
      assertions.equal("unlock", command.name)
      assertions.equal("Unlock a game object", command.summary)
      assertions.equal("domain_events", command.capabilities[1])
      assertions.truthy(type(command.run) == "function")
      command.capabilities[1] = "scheduled_jobs"

      local commands = registry:commands()
      assertions.equal(1, #commands)
      assertions.equal("domain_events", commands[1].capabilities[1])
      assertions.equal(nil, commands[1].run)
      assertions.equal(1, registry:status().commands)
      assertions.equal(2, registry:status().max_commands)
    end,
  },
  {
    name = "sandbox registry rejects invalid definitions before mutation",
    run = function()
      local registry = assert(Registry.new())
      local command, command_error = registry:register("missing", { summary = "Missing callback" })
      assertions.falsy(command)
      assertions.equal("sandbox_command_error", command_error.kind)
      command, command_error = registry:register("unknown", definition({ extra = true }))
      assertions.falsy(command)
      assertions.equal("sandbox_command_error", command_error.kind)
      command, command_error =
        registry:register("bad-capability", definition({ capabilities = { "process" } }))
      assertions.falsy(command)
      assertions.equal("sandbox_command_error", command_error.kind)
      assertions.equal("unsupported_capability", command_error.detail.reason)
      assertions.equal(0, registry:status().commands)
      assertions.truthy(Registry.capability_supported("vfs.read"))
      assertions.truthy(Registry.capability_supported("vfs.write"))
      assertions.truthy(Registry.capability_supported("vfs.chdir"))
      assertions.falsy(Registry.capability_supported("virtual_fs_read"))
    end,
  },
  {
    name = "sandbox registry preserves deterministic registration order and failures",
    run = function()
      local registry = assert(Registry.new({ max_commands = 2 }))
      assert(registry:register("second", definition({ summary = "Second" })))
      assert(registry:register("first", definition({ summary = "First" })))
      local duplicate, duplicate_error =
        registry:register("first", definition({ summary = "Changed" }))
      assertions.falsy(duplicate)
      assertions.equal("sandbox_command_error", duplicate_error.kind)
      local full, full_error = registry:register("third", definition({ summary = "Third" }))
      assertions.falsy(full)
      assertions.equal("sandbox_command_error", full_error.kind)
      local commands = registry:commands()
      assertions.equal("second", commands[1].name)
      assertions.equal("first", commands[2].name)
      local missing, missing_error = registry:command("missing")
      assertions.falsy(missing)
      assertions.equal("sandbox_command_error", missing_error.kind)
      assertions.equal(2, registry:status().commands)
    end,
  },
  {
    name = "sandbox registry validates bounded construction and command names",
    run = function()
      local registry, registry_error = Registry.new({ max_commands = 0 })
      assertions.falsy(registry)
      assertions.equal("sandbox_command_error", registry_error.kind)
      registry, registry_error = Registry.new({ unknown = true })
      assertions.falsy(registry)
      assertions.equal("sandbox_command_error", registry_error.kind)
      registry = assert(Registry.new())
      local command, command_error = registry:register("", definition())
      assertions.falsy(command)
      assertions.equal("sandbox_command_error", command_error.kind)
      command, command_error = registry:register("invalid\0name", definition())
      assertions.falsy(command)
      assertions.equal("sandbox_command_error", command_error.kind)
    end,
  },
}
