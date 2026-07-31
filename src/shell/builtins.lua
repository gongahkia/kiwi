local Errors = require("runtime.errors")

local Builtins = {}

Builtins.contract = {
  names = "names() -> builtin_command_names",
  register = "register(registry) -> true | nil, error",
}

local definitions = {
  { name = "help", summary = "List available commands", usage = "usage: help [COMMAND]" },
  {
    capabilities = { "vfs.read" },
    name = "pwd",
    summary = "Print current directory",
    usage = "usage: pwd",
  },
  {
    capabilities = { "vfs.read" },
    name = "ls",
    summary = "List directory entries",
    usage = "usage: ls [PATH]",
  },
  {
    capabilities = { "vfs.read" },
    name = "cat",
    summary = "Write file bytes",
    usage = "usage: cat PATH",
  },
  {
    capabilities = { "vfs.write" },
    name = "write",
    summary = "Replace file bytes",
    usage = "usage: write PATH DATA",
  },
  {
    capabilities = { "vfs.write" },
    name = "mkdir",
    summary = "Create one directory",
    usage = "usage: mkdir PATH",
  },
  {
    capabilities = { "vfs.write" },
    name = "rm",
    summary = "Remove one file or empty directory",
    usage = "usage: rm PATH",
  },
  {
    capabilities = { "vfs.write" },
    name = "mv",
    summary = "Rename one path",
    usage = "usage: mv SOURCE DESTINATION",
  },
  {
    capabilities = { "vfs.chdir" },
    name = "cd",
    summary = "Change current directory",
    usage = "usage: cd PATH",
  },
}

local function command_error(message, detail)
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function unavailable()
  return command_error("sandbox built-in implementation is unavailable", {
    reason = "built_in_unavailable",
  })
end

local function copy_capabilities(value)
  local result = {}
  for index, capability in ipairs(value or {}) do
    result[index] = capability
  end
  return result
end

function Builtins.names()
  local result = {}
  for index, definition in ipairs(definitions) do
    result[index] = definition.name
  end
  return result
end

function Builtins.register(registry)
  if type(registry) ~= "table" or type(registry.register) ~= "function" then
    return command_error("sandbox built-ins require a command registry")
  end
  for _, definition in ipairs(definitions) do
    local registered, registration_error = registry:register(definition.name, {
      capabilities = copy_capabilities(definition.capabilities),
      run = function()
        return unavailable()
      end,
      summary = definition.summary,
      usage = definition.usage,
    })
    if not registered then
      return nil, registration_error
    end
  end
  return true
end

return Builtins
