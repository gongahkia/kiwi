local Errors = require("runtime.errors")
local Completion = require("shell.completion")
local Dispatcher = require("shell.dispatcher")
local History = require("shell.history")
local Registry = require("shell.registry")
local Scheduler = require("shell.scheduler")
local Tokenizer = require("shell.tokenizer")
local VirtualFS = require("shell.virtual_fs")

local Session = {}
local session_mt = {}
session_mt.__index = session_mt

Session.contract = {
  complete = "complete(bytes, cursor_offset) -> completion_result | nil, error",
  destroy = "destroy() -> true",
  dispatch = "dispatch(bytes, context) -> command_dispatch | nil, error",
  advance = "advance(delta_us) -> scheduler_advance | nil, error",
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
      and name ~= "scheduler_limits"
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
  local scheduler, scheduler_error = Scheduler.new(value.scheduler_limits)
  if not scheduler then
    return nil, scheduler_error
  end
  local filesystem, filesystem_error = VirtualFS.new(value.filesystem)
  if not filesystem then
    scheduler:destroy()
    return nil, filesystem_error
  end
  return {
    history = history,
    filesystem = filesystem,
    granted_capabilities = granted_capabilities,
    completion_limits = value.completion_limits,
    output_limits = value.output_limits,
    scheduler = scheduler,
    scheduler_limits = scheduler:status().limits,
    tokenizer_limits = tokenizer_limits,
  }
end

local function scheduler_error(message, reason)
  return command_error(message, { reason = reason })
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

local function readonly(values, name)
  return setmetatable({}, {
    __index = values,
    __metatable = false,
    __newindex = function()
      error(name .. " is immutable")
    end,
  })
end

local function has_capability(capabilities, name)
  for _, capability in ipairs(capabilities) do
    if capability == name then
      return true
    end
  end
  return false
end

local function filesystem_capabilities(capabilities)
  local result = {}
  for _, capability in ipairs(capabilities) do
    if capability == "vfs.chdir" or capability == "vfs.read" or capability == "vfs.write" then
      result[capability] = true
    end
  end
  return result
end

local function jobs_facade(session, owner, operation_state)
  local active = true
  local methods = {}
  local function open()
    if not active or owner.closed then
      return scheduler_error("sandbox scheduler is closed", "scheduling_closed")
    end
    return true
  end
  methods.schedule = function(_, delay_us, callback)
    local available, available_error = open()
    if not available then
      return nil, available_error
    end
    return session:_schedule_job(owner, delay_us, callback, operation_state)
  end
  methods.cancel = function(_, job_id)
    local available, available_error = open()
    if not available then
      return nil, available_error
    end
    local pending, pending_error = session.scheduler:is_pending(job_id)
    if not pending and pending_error then
      return nil, pending_error
    end
    if not owner.pending[job_id] then
      return { cancelled = false }
    end
    return session.scheduler:cancel(job_id)
  end
  methods.is_pending = function(_, job_id)
    local available, available_error = open()
    if not available then
      return nil, available_error
    end
    local pending, pending_error = session.scheduler:is_pending(job_id)
    if not pending and pending_error then
      return nil, pending_error
    end
    return pending and owner.pending[job_id] == true
  end
  return readonly(methods, "sandbox scheduler facade"), function()
    active = false
  end
end

function session_mt:_remove_owner(owner)
  if owner.pending_count == 0 then
    self.job_owners[owner.invocation] = nil
  end
end

function session_mt:_finish_job(owner, job_id, state, error_value)
  if owner.pending[job_id] then
    owner.pending[job_id] = nil
    owner.pending_count = owner.pending_count - 1
    owner.invocation:release_hold()
  end
  if state == "failed" then
    owner.closed = true
    owner.invocation:fail(error_value)
    self.scheduler:cancel_owner(owner.token)
  end
  self:_remove_owner(owner)
end

function session_mt:_run_job(owner, callback, scheduler_context)
  if owner.closed then
    return scheduler_error("sandbox scheduler is closed", "scheduling_closed")
  end
  local operation_state = { operations = 0, zero_delay_jobs = 0 }
  local values = {
    due_us = scheduler_context.due_us,
    execution_sequence = scheduler_context.execution_sequence,
    job_id = scheduler_context.job_id,
    logical_time_us = scheduler_context.logical_time_us,
    writer = owner.invocation:writer(),
  }
  local close_facades = {}
  if next(owner.filesystem_capabilities) ~= nil then
    values.fs, close_facades[#close_facades + 1] =
      facade(self.filesystem, owner.filesystem_capabilities)
  end
  values.jobs, close_facades[#close_facades + 1] = jobs_facade(self, owner, operation_state)
  local callback_context = readonly(values, "sandbox scheduler callback context")
  local ok, result, callback_error = pcall(callback, callback_context)
  for index = #close_facades, 1, -1 do
    close_facades[index]()
  end
  if not ok then
    error(result)
  end
  return result, callback_error
end

function session_mt:_schedule_job(owner, delay_us, callback, operation_state)
  if type(callback) ~= "function" then
    return scheduler_error("sandbox scheduler callback must be a function", "resource_limit")
  end
  if operation_state.operations >= self.scheduler_limits.max_operations_per_callback then
    return scheduler_error(
      "sandbox scheduler callback operation limit is reached",
      "resource_limit"
    )
  end
  if owner.jobs_created >= self.scheduler_limits.max_invocation_jobs then
    return scheduler_error("sandbox scheduler invocation job limit is reached", "resource_limit")
  end
  if
    delay_us == 0
    and operation_state.zero_delay_jobs >= self.scheduler_limits.max_zero_delay_jobs_per_callback
  then
    return scheduler_error("sandbox scheduler zero-delay job limit is reached", "resource_limit")
  end
  local held, hold_error = owner.invocation:hold()
  if not held then
    return nil, hold_error
  end
  local job_id, schedule_error = self.scheduler:schedule(delay_us, function(context)
    return self:_run_job(owner, callback, context)
  end, {
    on_finish = function(id, state, error_value)
      self:_finish_job(owner, id, state, error_value)
    end,
    owner = owner.token,
  })
  if not job_id then
    owner.invocation:release_hold()
    return nil, schedule_error
  end
  operation_state.operations = operation_state.operations + 1
  if delay_us == 0 then
    operation_state.zero_delay_jobs = operation_state.zero_delay_jobs + 1
  end
  owner.jobs_created = owner.jobs_created + 1
  owner.pending[job_id] = true
  owner.pending_count = owner.pending_count + 1
  return job_id
end

function session_mt:_cancel_invocation_jobs(invocation)
  local owner = self.job_owners[invocation]
  if not owner then
    return 0
  end
  owner.closed = true
  local cancelled = self.scheduler:cancel_owner(owner.token)
  self:_remove_owner(owner)
  return cancelled
end

function session_mt:_build_invocation_context(command, invocation, context)
  local callback_context, close_filesystem =
    invocation_context(context, self.filesystem, command.capabilities)
  if not has_capability(command.capabilities, "jobs.schedule") then
    return callback_context, close_filesystem
  end
  if self.next_owner_token > 4294967295 then
    return scheduler_error("sandbox scheduler owner identifiers are exhausted", "resource_limit")
  end
  local owner = {
    closed = false,
    filesystem_capabilities = filesystem_capabilities(command.capabilities),
    invocation = invocation,
    jobs_created = 0,
    pending = {},
    pending_count = 0,
    token = self.next_owner_token,
  }
  self.next_owner_token = self.next_owner_token + 1
  self.job_owners[invocation] = owner
  if type(callback_context) ~= "table" then
    callback_context = copied_context(context)
  end
  local operation_state = { operations = 0, zero_delay_jobs = 0 }
  local close_jobs
  callback_context.jobs, close_jobs = jobs_facade(self, owner, operation_state)
  return callback_context,
    function()
      close_jobs()
      if close_filesystem then
        close_filesystem()
      end
      self:_remove_owner(owner)
    end
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
    job_owners = {},
    last_history_diagnostic = nil,
    next_owner_token = 1,
    scheduler = settings.scheduler,
    scheduler_limits = settings.scheduler_limits,
    tokenizer_limits = settings.tokenizer_limits,
  }, session_mt)
end

function session_mt:complete(bytes, cursor_offset)
  if self.destroyed then
    return command_error("sandbox session is destroyed", { reason = "session_closed" })
  end
  return self.completion:complete(bytes, cursor_offset)
end

function session_mt:advance(delta_us)
  if self.destroyed then
    return command_error("sandbox session is destroyed", { reason = "session_closed" })
  end
  return self.scheduler:advance(delta_us)
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
  local outcome, dispatch_error = self.dispatcher:dispatch(bytes, context, {
    context_factory = function(dispatch_command, invocation, original_context)
      return self:_build_invocation_context(dispatch_command, invocation, original_context)
    end,
    on_cancel = function(invocation)
      self:_cancel_invocation_jobs(invocation)
    end,
  })
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
    scheduler = self.scheduler:status(),
  }
end

function session_mt:destroy()
  if self.destroyed then
    return true
  end
  self.last_history_diagnostic = nil
  self.scheduler:destroy()
  self.job_owners = {}
  self.filesystem:destroy()
  self.history_value:clear()
  self.destroyed = true
  return true
end

return Session
