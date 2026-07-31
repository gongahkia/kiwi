local assertions = require("support.assertions")
local Builtins = require("shell.builtins")
local Registry = require("shell.registry")

local expected = {
  { name = "help", usage = "usage: help [COMMAND]" },
  { capability = "vfs.read", name = "pwd", usage = "usage: pwd" },
  { capability = "vfs.read", name = "ls", usage = "usage: ls [PATH]" },
  { capability = "vfs.read", name = "cat", usage = "usage: cat PATH" },
  { capability = "vfs.write", name = "write", usage = "usage: write PATH DATA" },
  { capability = "vfs.write", name = "mkdir", usage = "usage: mkdir PATH" },
  { capability = "vfs.write", name = "rm", usage = "usage: rm PATH" },
  { capability = "vfs.write", name = "mv", usage = "usage: mv SOURCE DESTINATION" },
  { capability = "vfs.chdir", name = "cd", usage = "usage: cd PATH" },
}

return {
  {
    name = "sandbox built-ins register fixed metadata through the normal registry",
    run = function()
      local registry = assert(Registry.new())
      assertions.truthy(Builtins.register(registry))
      local names = Builtins.names()
      local commands = registry:commands()
      assertions.equal(9, #names)
      assertions.equal(9, #commands)
      for index, value in ipairs(expected) do
        assertions.equal(value.name, names[index])
        assertions.equal(value.name, commands[index].name)
        assertions.equal(value.usage, commands[index].usage)
        if value.capability then
          assertions.equal(value.capability, commands[index].capabilities[1])
        else
          assertions.equal(0, #commands[index].capabilities)
        end
      end
      commands[1].usage = "changed"
      assertions.equal(expected[1].usage, assert(registry:describe("help")).usage)
    end,
  },
  {
    name = "sandbox built-in duplicate registration follows registry validation",
    run = function()
      local registry = assert(Registry.new())
      assertions.truthy(Builtins.register(registry))
      local registered, registration_error = Builtins.register(registry)
      assertions.falsy(registered)
      assertions.equal("sandbox_command_error", registration_error.kind)
      assertions.equal(9, registry:status().commands)
    end,
  },
  {
    name = "sandbox registry validates and isolates optional command usage metadata",
    run = function()
      local registry = assert(Registry.new())
      assert(registry:register("custom", {
        run = function() end,
        summary = "Custom command",
        usage = "usage: custom VALUE",
      }))
      local description = assert(registry:describe("custom"))
      assertions.equal("usage: custom VALUE", description.usage)
      assertions.equal(nil, description.run)
      local command, command_error = registry:register("invalid", {
        run = function() end,
        summary = "Invalid command",
        usage = "",
      })
      assertions.falsy(command)
      assertions.equal("sandbox_command_error", command_error.kind)
    end,
  },
}
