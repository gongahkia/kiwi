local Errors = require("runtime.errors")
local Completion = require("shell.completion")
local Dispatcher = require("shell.dispatcher")
local History = require("shell.history")
local Registry = require("shell.registry")
local Tokenizer = require("shell.tokenizer")
local VirtualFS = require("shell.virtual_fs")

local Session = {}
local session_mt = {}
session_mt.__index = session_mt

Session.contract = {
  complete = "complete(bytes, cursor_offset) -> completion_result | nil, error",
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
    if
      name ~= "completion_limits"
      and name ~= "filesystem"
      and name ~= "granted_capabilities"
      and name ~= "history_limits"
      and name ~= "output_limits"
      and name ~= "tokenizer_limits"
    then
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
  local grants = value.granted_capabilities or {}
  if type(grants) ~= "table" then
    return command_error("sandbox session granted capabilities must be an array")
  end
  local grant_length = #grants
  for key in pairs(grants) do
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > grant_length then
      return command_error("sandbox session granted capabilities must be a dense array")
    end
  end
  local granted_capabilities = {}
  for _, capability in ipairs(grants) do
    if not Registry.capability_supported(capability) then
      return command_error("sandbox session granted capability is unsupported", {
        capability = capability,
        reason = "unsupported_capability",
      })
    end
    if granted_capabilities[capability] then
      return command_error("sandbox session granted capabilities must be unique", {
        capability = capability,
        reason = "unsupported_capability",
      })
    end
    granted_capabilities[capability] = true
  end
  local filesystem, filesystem_error = VirtualFS.new(value.filesystem)
  if not filesystem then
    return nil, filesystem_error
  end
  return {
    history = history,
    filesystem = filesystem,
    granted_capabilities = granted_capabilities,
    completion_limits = value.completion_limits,
    output_limits = value.output_limits,
    tokenizer_limits = tokenizer_limits,
  }
end

local function copied_context(value)
  if type(value) ~= "table" then
    return { host_context = value }
  end
  local result = {}
  for name, field in pairs(value) do
    if name ~= "fs" then
      result[name] = field
    end
  end
  return result
end

local function capability_error(capability)
  return command_error("sandbox command capability is not granted", {
    capability = capability,
    reason = "capability_denied",
  })
end

local function facade(filesystem, command_capabilities)
  local active = true
  local methods = {}
  local function call(capability, method, ...)
    if not active or not command_capabilities[capability] then
      return capability_error(capability)
    end
    return filesystem[method](filesystem, ...)
  end
  if command_capabilities["vfs.read"] then
    methods.get_cwd = function()
      return call("vfs.read", "get_cwd")
    end
    methods.list = function(_, ...)
      return call("vfs.read", "list", ...)
    end
    methods.read_file = function(_, ...)
      return call("vfs.read", "read_file", ...)
    end
    methods.stat = function(_, ...)
      return call("vfs.read", "stat", ...)
    end
  end
  if command_capabilities["vfs.write"] then
    methods.append_file = function(_, ...)
      return call("vfs.write", "append_file", ...)
    end
    methods.make_directory = function(_, ...)
      return call("vfs.write", "make_directory", ...)
    end
    methods.remove = function(_, ...)
      return call("vfs.write", "remove", ...)
    end
    methods.rename = function(_, ...)
      return call("vfs.write", "rename", ...)
    end
    methods.write_file = function(_, ...)
      return call("vfs.write", "write_file", ...)
    end
  end
  if command_capabilities["vfs.chdir"] then
    methods.change_directory = function(_, ...)
      return call("vfs.chdir", "change_directory", ...)
    end
  end
  local object = setmetatable({}, {
    __index = methods,
    __newindex = function()
      error("sandbox filesystem facade is immutable")
    end,
  })
  return object, function()
    active = false
  end
end

local function invocation_context(context, filesystem, capabilities)
  local command_capabilities = {}
  for _, capability in ipairs(capabilities) do
    if capability == "vfs.chdir" or capability == "vfs.read" or capability == "vfs.write" then
      command_capabilities[capability] = true
    end
  end
  if next(command_capabilities) == nil then
    if type(context) == "table" and context.fs ~= nil then
      return copied_context(context)
    end
    return context
  end
  local result = copied_context(context)
  local filesystem_facade, close = facade(filesystem, command_capabilities)
  result.fs = filesystem_facade
  return result, close
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
  local completion, completion_error = Completion.new(registry, settings.completion_limits)
  if not completion then
    return nil, completion_error
  end
  return setmetatable({
    completion = completion,
    destroyed = false,
    dispatcher = dispatcher,
    filesystem = settings.filesystem,
    granted_capabilities = settings.granted_capabilities,
    history_value = settings.history,
    last_history_diagnostic = nil,
    tokenizer_limits = settings.tokenizer_limits,
  }, session_mt)
end

function session_mt:complete(bytes, cursor_offset)
  if self.destroyed then
    return command_error("sandbox session is destroyed", { reason = "session_closed" })
  end
  return self.completion:complete(bytes, cursor_offset)
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
  if #argv == 0 then
    return self.dispatcher:dispatch(bytes, context)
  end
  local command, command_lookup_error = self.dispatcher.registry:command(argv[1])
  if not command then
    return nil, command_lookup_error
  end
  for _, capability in ipairs(command.capabilities) do
    if not self.granted_capabilities[capability] then
      return capability_error(capability)
    end
  end
  local callback_context, close_facade = invocation_context(context, self.filesystem, command.capabilities)
  local outcome, dispatch_error = self.dispatcher:dispatch(bytes, callback_context)
  if close_facade then
    close_facade()
  end
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
    filesystem = self.filesystem:status(),
    history = self.history_value:status(),
    last_history_diagnostic = copy_error(self.last_history_diagnostic),
  }
end

function session_mt:destroy()
  if self.destroyed then
    return true
  end
  self.last_history_diagnostic = nil
  self.filesystem:destroy()
  self.history_value:clear()
  self.destroyed = true
  return true
end

return Session
