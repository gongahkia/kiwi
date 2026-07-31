local Errors = require("runtime.errors")

local Registry = {}
local registry_mt = {}
registry_mt.__index = registry_mt

Registry.contract = {
  capability_supported = "capability_supported(name) -> boolean",
  command = "command(name) -> command_definition | nil, error",
  commands = "commands() -> command_descriptors",
  constructor = "new(options?) -> command_registry | nil, error",
  describe = "describe(name) -> command_descriptor | nil, error",
  register = "register(name, definition) -> true | nil, error",
  status = "status() -> command_registry_status",
}

local DEFAULT_MAX_COMMANDS = 128
local MAX_CAPABILITIES = 8
local MAX_COMMAND_NAME_BYTES = 64
local MAX_SUMMARY_BYTES = 256
local MAX_USAGE_BYTES = 128

local capabilities = {
  completion = true,
  deterministic_random = true,
  domain_events = true,
  scheduled_jobs = true,
  ["vfs.chdir"] = true,
  ["vfs.read"] = true,
  ["vfs.write"] = true,
}

function Registry.capability_supported(value)
  return type(value) == "string" and capabilities[value] == true
end

local function command_error(message, detail)
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function positive_integer(value, name, maximum)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > maximum then
    return command_error(name .. " must be an integer from 1 to " .. maximum, { provided = value })
  end
  return value
end

local function options(value)
  if value == nil then
    value = {}
  end
  if type(value) ~= "table" then
    return command_error("command registry options must be a table")
  end
  for name in pairs(value) do
    if name ~= "max_commands" then
      return command_error("command registry option is unsupported", { option = name })
    end
  end
  local max_commands, max_error = positive_integer(
    value.max_commands or DEFAULT_MAX_COMMANDS,
    "command registry maximum commands",
    1024
  )
  if not max_commands then
    return nil, max_error
  end
  return { max_commands = max_commands }
end

local function dense_array(value, name)
  if type(value) ~= "table" then
    return command_error(name .. " must be an array")
  end
  local length = #value
  for key in pairs(value) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
      return command_error(name .. " must be a dense array")
    end
  end
  return length
end

local function copy_capabilities(value)
  local length, length_error = dense_array(value, "command capabilities")
  if not length then
    return nil, length_error
  end
  if length > MAX_CAPABILITIES then
    return command_error("command capabilities exceed the configured bound")
  end
  local result = {}
  local seen = {}
  for index, capability in ipairs(value) do
    if not Registry.capability_supported(capability) then
      return command_error("command capability is unsupported", {
        capability = capability,
        reason = "unsupported_capability",
      })
    end
    if seen[capability] then
      return command_error("command capabilities must be unique", { capability = capability })
    end
    seen[capability] = true
    result[index] = capability
  end
  return result
end

local function name(value)
  if type(value) ~= "string" or #value == 0 or #value > MAX_COMMAND_NAME_BYTES then
    return command_error("command name must be a non-empty bounded byte string")
  end
  if value:find("\0", 1, true) then
    return command_error("command name must not contain NUL")
  end
  return value
end

local function definition(value)
  if type(value) ~= "table" then
    return command_error("command definition must be a table")
  end
  for field in pairs(value) do
    if
      field ~= "capabilities"
      and field ~= "complete"
      and field ~= "run"
      and field ~= "summary"
      and field ~= "usage"
    then
      return command_error("command definition contains an unsupported field", { field = field })
    end
  end
  if
    type(value.summary) ~= "string"
    or #value.summary == 0
    or #value.summary > MAX_SUMMARY_BYTES
  then
    return command_error("command summary must be a non-empty bounded byte string")
  end
  if type(value.run) ~= "function" then
    return command_error("command run callback must be a function")
  end
  if
    value.usage ~= nil
    and (type(value.usage) ~= "string" or #value.usage == 0 or #value.usage > MAX_USAGE_BYTES)
  then
    return command_error("command usage must be a non-empty bounded byte string")
  end
  if value.complete ~= nil and type(value.complete) ~= "function" then
    return command_error("command complete callback must be a function")
  end
  local command_capabilities = value.capabilities or {}
  local copied_capabilities, capabilities_error = copy_capabilities(command_capabilities)
  if not copied_capabilities then
    return nil, capabilities_error
  end
  return {
    capabilities = copied_capabilities,
    complete = value.complete,
    run = value.run,
    summary = value.summary,
    usage = value.usage,
  }
end

local function copy_command(name_value, value, callbacks)
  local result = {
    capabilities = {},
    name = name_value,
    summary = value.summary,
    usage = value.usage,
  }
  for index, capability in ipairs(value.capabilities) do
    result.capabilities[index] = capability
  end
  if callbacks then
    result.complete = value.complete
    result.run = value.run
  end
  return result
end

function Registry.new(configuration)
  local settings, settings_error = options(configuration)
  if not settings then
    return nil, settings_error
  end
  return setmetatable({
    by_name = {},
    max_commands = settings.max_commands,
    ordered_names = {},
  }, registry_mt)
end

function registry_mt:register(command_name, command_definition)
  local valid_name, name_error = name(command_name)
  if not valid_name then
    return nil, name_error
  end
  local valid_definition, definition_error = definition(command_definition)
  if not valid_definition then
    return nil, definition_error
  end
  if self.by_name[valid_name] then
    return command_error("command is already registered", { name = valid_name })
  end
  if #self.ordered_names >= self.max_commands then
    return command_error("command registry is full", { maximum = self.max_commands })
  end
  self.by_name[valid_name] = valid_definition
  self.ordered_names[#self.ordered_names + 1] = valid_name
  return true
end

function registry_mt:command(command_name)
  local valid_name, name_error = name(command_name)
  if not valid_name then
    return nil, name_error
  end
  local command_definition = self.by_name[valid_name]
  if not command_definition then
    return command_error("command is not registered", { name = valid_name })
  end
  return copy_command(valid_name, command_definition, true)
end

function registry_mt:commands()
  local result = {}
  for index, command_name in ipairs(self.ordered_names) do
    result[index] = copy_command(command_name, self.by_name[command_name], false)
  end
  return result
end

function registry_mt:describe(command_name)
  local valid_name, name_error = name(command_name)
  if not valid_name then
    return nil, name_error
  end
  local command_definition = self.by_name[valid_name]
  if not command_definition then
    return command_error("command is not registered", { name = valid_name })
  end
  return copy_command(valid_name, command_definition, false)
end

function registry_mt:status()
  return { commands = #self.ordered_names, max_commands = self.max_commands }
end

return Registry
