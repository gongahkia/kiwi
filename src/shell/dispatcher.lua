local Errors = require("runtime.errors")
local Output = require("shell.output")
local Tokenizer = require("shell.tokenizer")

local Dispatcher = {}
local dispatcher_mt = {}
dispatcher_mt.__index = dispatcher_mt

Dispatcher.contract = {
  dispatch = "dispatch(bytes, context, options?) -> command_dispatch | nil, error",
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
    if name ~= "limits" and name ~= "output_limits" then
      has_unsupported_option = true
    end
  end
  if has_unsupported_option then
    return command_error("sandbox command dispatcher option is unsupported")
  end
  local tokenizer_limits, tokenizer_error = Tokenizer.normalise_limits(value.limits)
  if not tokenizer_limits then
    return nil, tokenizer_error
  end
  local output_limits, output_error = Output.normalise_limits(value.output_limits)
  if not output_limits then
    return nil, output_error
  end
  return { output_limits = output_limits, tokenizer_limits = tokenizer_limits }
end

function Dispatcher.new(registry, configuration)
  if type(registry) ~= "table" or type(registry.command) ~= "function" then
    return command_error("sandbox command dispatcher requires a command registry")
  end
  local settings, settings_error = options(configuration)
  if not settings then
    return nil, settings_error
  end
  return setmetatable({
    output_limits = settings.output_limits,
    output_sequence = 1,
    registry = registry,
    tokenizer_limits = settings.tokenizer_limits,
  }, dispatcher_mt)
end

local function output_sequence(dispatcher)
  if dispatcher.output_sequence > 4294967295 then
    return nil
  end
  local sequence = dispatcher.output_sequence
  dispatcher.output_sequence = sequence + 1
  return sequence
end

local function outcome(command, argv, invocation, result)
  local output_status = invocation:status()
  return {
    argv = copy_argv(argv),
    command = command.name,
    dispatched = true,
    failure = output_status.failure,
    failed = output_status.failed,
    invocation = invocation,
    result = result,
  }
end

local function dispatch_options(value)
  if value == nil then
    return {}
  end
  if type(value) ~= "table" then
    return command_error("sandbox command dispatch options must be a table")
  end
  for name in pairs(value) do
    if name ~= "context_factory" and name ~= "on_cancel" then
      return command_error("sandbox command dispatch option is unsupported")
    end
  end
  if value.context_factory ~= nil and type(value.context_factory) ~= "function" then
    return command_error("sandbox command context factory must be a function")
  end
  if value.on_cancel ~= nil and type(value.on_cancel) ~= "function" then
    return command_error("sandbox command cancellation callback must be a function")
  end
  return value
end

function dispatcher_mt:dispatch(bytes, context, configuration)
  local settings, settings_error = dispatch_options(configuration)
  if not settings then
    return nil, settings_error
  end
  local argv, token_error = Tokenizer.tokenize(bytes, self.tokenizer_limits)
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
  local invocation
  local invocation_error
  invocation, invocation_error = Output.new(self.output_limits, function()
    return output_sequence(self)
  end, function()
    if settings.on_cancel then
      settings.on_cancel(invocation)
    end
  end)
  if not invocation then
    return nil, invocation_error
  end
  local callback_context = context
  local close_context = nil
  if settings.context_factory then
    local built, close_or_error = settings.context_factory(command, invocation, context)
    if built == nil and Errors.is(close_or_error) then
      invocation:fail(close_or_error)
      return outcome(command, argv, invocation)
    end
    callback_context = built
    close_context = close_or_error
  end
  local callback_argv = copy_argv(argv)
  local ok, result, callback_error_value =
    pcall(command.run, callback_context, callback_argv, invocation:writer())
  if type(close_context) == "function" then
    pcall(close_context)
  end
  if not ok then
    local _, callback_error = command_error("sandbox command callback failed", {
      name = command.name,
      reason = "command_failed",
    })
    invocation:fail(callback_error)
    return outcome(command, argv, invocation)
  end
  if result == nil and Errors.is(callback_error_value) then
    invocation:fail(callback_error_value)
    return outcome(command, argv, invocation)
  end
  invocation:complete()
  return outcome(command, argv, invocation, result)
end

return Dispatcher
