local Errors = require("runtime.errors")
local Dispatcher = require("shell.dispatcher")
local History = require("shell.history")
local Tokenizer = require("shell.tokenizer")

local Session = {}
local session_mt = {}
session_mt.__index = session_mt

Session.contract = {
  destroy = "destroy() -> true",
  dispatch = "dispatch(bytes, context) -> command_dispatch | nil, error",
  history = "history() -> command_history",
  reset_history = "reset_history() -> true",
  status = "status() -> sandbox_session_status",
}

local function command_error(message, detail)
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function copy_error(error_value)
  if error_value == nil then
    return nil
  end
  local detail = nil
  if type(error_value.detail) == "table" then
    detail = {}
    for name, value in pairs(error_value.detail) do
      detail[name] = value
    end
  end
  return { detail = detail, kind = error_value.kind, message = error_value.message }
end

local function options(value)
  if value == nil then
    value = {}
  end
  if type(value) ~= "table" then
    return command_error("sandbox session options must be a table")
  end
  local has_unsupported_option = false
  for name in pairs(value) do
    if name ~= "history_limits" and name ~= "output_limits" and name ~= "tokenizer_limits" then
      has_unsupported_option = true
    end
  end
  if has_unsupported_option then
    return command_error("sandbox session option is unsupported")
  end
  local tokenizer_limits, tokenizer_error = Tokenizer.normalise_limits(value.tokenizer_limits)
  if not tokenizer_limits then
    return nil, tokenizer_error
  end
  local history, history_error = History.new(value.history_limits)
  if not history then
    return nil, history_error
  end
  return {
    history = history,
    output_limits = value.output_limits,
    tokenizer_limits = tokenizer_limits,
  }
end

function Session.new(registry, configuration)
  local settings, settings_error = options(configuration)
  if not settings then
    return nil, settings_error
  end
  local dispatcher, dispatcher_error = Dispatcher.new(registry, {
    limits = settings.tokenizer_limits,
    output_limits = settings.output_limits,
  })
  if not dispatcher then
    return nil, dispatcher_error
  end
  return setmetatable({
    destroyed = false,
    dispatcher = dispatcher,
    history_value = settings.history,
    last_history_diagnostic = nil,
    tokenizer_limits = settings.tokenizer_limits,
  }, session_mt)
end

function session_mt:dispatch(bytes, context)
  if self.destroyed then
    return command_error("sandbox session is destroyed", { reason = "session_closed" })
  end
  local argv, tokenizer_error = Tokenizer.tokenize(bytes, self.tokenizer_limits)
  if not argv then
    return nil, tokenizer_error
  end
  self.last_history_diagnostic = nil
  if #argv > 0 and not self.history_value:status().disabled then
    local admitted, admission_error = self.history_value:append(bytes)
    if not admitted then
      self.last_history_diagnostic = admission_error
    end
  end
  local outcome, dispatch_error = self.dispatcher:dispatch(bytes, context)
  if outcome and self.last_history_diagnostic then
    outcome.history_diagnostic = copy_error(self.last_history_diagnostic)
  end
  return outcome, dispatch_error
end

function session_mt:history()
  return self.history_value
end

function session_mt:reset_history()
  self.last_history_diagnostic = nil
  return self.history_value:clear()
end

function session_mt:status()
  return {
    destroyed = self.destroyed,
    history = self.history_value:status(),
    last_history_diagnostic = copy_error(self.last_history_diagnostic),
  }
end

function session_mt:destroy()
  if self.destroyed then
    return true
  end
  self.last_history_diagnostic = nil
  self.history_value:clear()
  self.destroyed = true
  return true
end

return Session
