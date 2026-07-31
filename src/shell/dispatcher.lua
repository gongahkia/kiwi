local Errors = require("runtime.errors")
local Tokenizer = require("shell.tokenizer")

local Dispatcher = {}
local dispatcher_mt = {}
dispatcher_mt.__index = dispatcher_mt

Dispatcher.contract = {
  dispatch = "dispatch(bytes, context) -> command_dispatch | nil, error",
  new = "new(registry, options?) -> command_dispatcher | nil, error",
}

local function command_error(message, detail)
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function copy_argv(argv)
  local result = {}
  for index, argument in ipairs(argv) do
    result[index] = argument
  end
  return result
end

local function options(value)
  if value == nil then
    value = {}
  end
  if type(value) ~= "table" then
    return command_error("sandbox command dispatcher options must be a table")
  end
  local has_unsupported_option = false
  for name in pairs(value) do
    if name ~= "limits" then
      has_unsupported_option = true
    end
  end
  if has_unsupported_option then
    return command_error("sandbox command dispatcher option is unsupported")
  end
  return Tokenizer.normalise_limits(value.limits)
end

function Dispatcher.new(registry, configuration)
  if type(registry) ~= "table" or type(registry.command) ~= "function" then
    return command_error("sandbox command dispatcher requires a command registry")
  end
  local limits, limits_error = options(configuration)
  if not limits then
    return nil, limits_error
  end
  return setmetatable({ limits = limits, registry = registry }, dispatcher_mt)
end

function dispatcher_mt:dispatch(bytes, context)
  local argv, token_error = Tokenizer.tokenize(bytes, self.limits)
  if not argv then
    return nil, token_error
  end
  if #argv == 0 then
    return { argv = {}, dispatched = false }
  end
  local command, command_error_value = self.registry:command(argv[1])
  if not command then
    return nil, command_error_value
  end
  local callback_argv = copy_argv(argv)
  local ok, result = pcall(command.run, context, callback_argv)
  if not ok then
    return command_error("sandbox command callback failed", {
      name = command.name,
      reason = "command_failed",
    })
  end
  return {
    argv = copy_argv(argv),
    command = command.name,
    dispatched = true,
    result = result,
  }
end

return Dispatcher
