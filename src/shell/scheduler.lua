local Errors = require("runtime.errors")

local Scheduler = {}
local scheduler_mt = {}
scheduler_mt.__index = scheduler_mt

Scheduler.contract = {
  advance = "advance(delta_us) -> scheduler_advance | nil, error",
  cancel = "cancel(job_id) -> cancellation_result | nil, error",
  cancel_owner = "cancel_owner(owner) -> cancelled_job_count",
  constructor = "new(limits?) -> sandbox_scheduler | nil, error",
  destroy = "destroy() -> true",
  is_pending = "is_pending(job_id) -> boolean | nil, error",
  normalise_limits = "normalise_limits(limits?) -> scheduler_limits | nil, error",
  schedule = "schedule(delay_us, callback, options?) -> job_id | nil, error",
  status = "status() -> scheduler_status",
}

local MAX_U32 = 4294967295
local default_limits = {
  max_active_jobs = 64,
  max_advance_us = 1000000,
  max_callback_metadata_bytes = 256,
  max_callbacks_per_advance = 16,
  max_delay_us = 60000000,
  max_invocation_jobs = 16,
  max_logical_time_us = MAX_U32,
  max_operations_per_callback = 16,
  max_zero_delay_jobs_per_callback = 8,
}

local allowed_limits = {}
for name in pairs(default_limits) do
  allowed_limits[name] = true
end

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

local function positive_integer(value, name, maximum)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > maximum then
    return command_error(name .. " must be a positive bounded integer", {
      limit = maximum,
      minimum = 1,
      provided = value,
      reason = "resource_limit",
    })
  end
  return value
end

local function valid_job_id(value)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > MAX_U32 then
    return command_error("sandbox scheduler job id is unknown", { reason = "unknown_job" })
  end
  return value
end

function Scheduler.normalise_limits(value)
  if value == nil then
    value = {}
  end
  if type(value) ~= "table" then
    return command_error("sandbox scheduler limits must be a table", { reason = "resource_limit" })
  end
  for name in pairs(value) do
    if not allowed_limits[name] then
      return command_error("sandbox scheduler limit is unsupported", { reason = "resource_limit" })
    end
  end
  local result = {}
  for name, default in pairs(default_limits) do
    local limit, limit_error = positive_integer(value[name] or default, name, default)
    if not limit then
      return nil, limit_error
    end
    result[name] = limit
  end
  if result.max_delay_us > result.max_logical_time_us then
    return command_error("sandbox scheduler delay exceeds logical time bound", {
      reason = "resource_limit",
    })
  end
  return result
end

local function copy_limits(limits)
  local result = {}
  for name, value in pairs(limits) do
    result[name] = value
  end
  return result
end

local function job_less(left, right)
  return left.due_us < right.due_us
    or (left.due_us == right.due_us and left.insertion_sequence < right.insertion_sequence)
end

local function insert_job(jobs, job)
  local index = #jobs + 1
  while index > 1 and job_less(job, jobs[index - 1]) do
    jobs[index] = jobs[index - 1]
    index = index - 1
  end
  jobs[index] = job
end

local function pop_first(jobs)
  local first = jobs[1]
  for index = 2, #jobs do
    jobs[index - 1] = jobs[index]
  end
  jobs[#jobs] = nil
  return first
end

local function remove_id(jobs, id)
  for index, job in ipairs(jobs) do
    if job.id == id then
      for remaining = index + 1, #jobs do
        jobs[remaining - 1] = jobs[remaining]
      end
      jobs[#jobs] = nil
      return job
    end
  end
  return nil
end

local function callback_failure(job, callback_error)
  local detail = { job_id = job.id, reason = "callback_failure" }
  if Errors.is(callback_error) and callback_error.detail and callback_error.detail.reason then
    detail.cause_reason = callback_error.detail.reason
  end
  local error_value =
    Errors.new("sandbox_command_error", "sandbox scheduled callback failed", detail)
  return error_value
end

local function context(job, time_us, execution_sequence)
  local values = {
    due_us = job.due_us,
    execution_sequence = execution_sequence,
    job_id = job.id,
    logical_time_us = time_us,
  }
  return setmetatable({}, {
    __index = values,
    __metatable = false,
    __newindex = function()
      error("sandbox scheduler callback context is immutable")
    end,
  })
end

local function finish(job, state, error_value)
  if job.on_finish then
    pcall(job.on_finish, job.id, state, copy_error(error_value))
  end
  job.callback = nil
  job.on_finish = nil
  job.owner = nil
end

function Scheduler.new(configuration)
  local limits, limits_error = Scheduler.normalise_limits(configuration)
  if not limits then
    return nil, limits_error
  end
  return setmetatable({
    advancing = false,
    destroyed = false,
    execution_sequence = 1,
    insertion_sequence = 1,
    jobs = {},
    limits = limits,
    next_job_id = 1,
    time_us = 0,
  }, scheduler_mt)
end

function scheduler_mt:schedule(delay_us, callback, options)
  if self.destroyed then
    return command_error("sandbox scheduler is closed", { reason = "scheduling_closed" })
  end
  if type(delay_us) ~= "number" or delay_us % 1 ~= 0 or delay_us < 0 then
    return command_error("sandbox scheduler delay is invalid", { reason = "invalid_delay" })
  end
  if delay_us > self.limits.max_delay_us then
    return command_error("sandbox scheduler delay exceeds its limit", {
      limit = self.limits.max_delay_us,
      reason = "delay_too_large",
    })
  end
  if delay_us > self.limits.max_logical_time_us - self.time_us then
    return command_error("sandbox scheduler logical time would overflow", {
      limit = self.limits.max_logical_time_us,
      reason = "logical_time_overflow",
    })
  end
  if type(callback) ~= "function" then
    return command_error(
      "sandbox scheduler callback must be a function",
      { reason = "resource_limit" }
    )
  end
  if options == nil then
    options = {}
  end
  if type(options) ~= "table" then
    return command_error("sandbox scheduler options must be a table", { reason = "resource_limit" })
  end
  for name in pairs(options) do
    if name ~= "on_finish" and name ~= "owner" then
      return command_error("sandbox scheduler option is unsupported", { reason = "resource_limit" })
    end
  end
  if options.on_finish ~= nil and type(options.on_finish) ~= "function" then
    return command_error("sandbox scheduler finish callback must be a function", {
      reason = "resource_limit",
    })
  end
  if
    options.owner ~= nil
    and (
      type(options.owner) ~= "number"
      or options.owner % 1 ~= 0
      or options.owner < 1
      or options.owner > MAX_U32
    )
  then
    return command_error("sandbox scheduler owner is invalid", { reason = "resource_limit" })
  end
  if #self.jobs >= self.limits.max_active_jobs then
    return command_error("sandbox scheduler is full", {
      limit = self.limits.max_active_jobs,
      reason = "scheduler_full",
    })
  end
  if self.next_job_id > MAX_U32 or self.insertion_sequence > MAX_U32 then
    return command_error(
      "sandbox scheduler identifiers are exhausted",
      { reason = "resource_limit" }
    )
  end
  local job = {
    callback = callback,
    due_us = self.time_us + delay_us,
    id = self.next_job_id,
    insertion_sequence = self.insertion_sequence,
    on_finish = options.on_finish,
    owner = options.owner,
  }
  insert_job(self.jobs, job)
  self.next_job_id = self.next_job_id + 1
  self.insertion_sequence = self.insertion_sequence + 1
  return job.id
end

function scheduler_mt:cancel(job_id)
  local id, id_error = valid_job_id(job_id)
  if not id then
    return nil, id_error
  end
  if self.destroyed then
    return { cancelled = false }
  end
  local job = remove_id(self.jobs, id)
  if not job then
    return { cancelled = false }
  end
  finish(job, "cancelled")
  return { cancelled = true }
end

function scheduler_mt:cancel_owner(owner)
  if self.destroyed then
    return 0
  end
  local cancelled = 0
  local index = 1
  while index <= #self.jobs do
    local job = self.jobs[index]
    if job.owner == owner then
      table.remove(self.jobs, index)
      finish(job, "cancelled")
      cancelled = cancelled + 1
    else
      index = index + 1
    end
  end
  return cancelled
end

function scheduler_mt:is_pending(job_id)
  local id, id_error = valid_job_id(job_id)
  if not id then
    return nil, id_error
  end
  if self.destroyed then
    return false
  end
  for _, job in ipairs(self.jobs) do
    if job.id == id then
      return true
    end
  end
  return false
end

function scheduler_mt:advance(delta_us)
  if self.destroyed then
    return command_error("sandbox scheduler is closed", { reason = "scheduling_closed" })
  end
  if self.advancing then
    return command_error(
      "sandbox scheduler advance is reentrant",
      { reason = "scheduler_reentrant" }
    )
  end
  if type(delta_us) ~= "number" or delta_us % 1 ~= 0 or delta_us < 0 then
    return command_error("sandbox scheduler advance is invalid", { reason = "invalid_delta_us" })
  end
  if delta_us > self.limits.max_advance_us then
    return command_error("sandbox scheduler advance exceeds its limit", {
      limit = self.limits.max_advance_us,
      reason = "advance_too_large",
    })
  end
  if delta_us > self.limits.max_logical_time_us - self.time_us then
    return command_error("sandbox scheduler logical time would overflow", {
      limit = self.limits.max_logical_time_us,
      reason = "logical_time_overflow",
    })
  end
  self.time_us = self.time_us + delta_us
  self.advancing = true
  local executed = 0
  local failures = {}
  while executed < self.limits.max_callbacks_per_advance do
    local job = self.jobs[1]
    if not job or job.due_us > self.time_us then
      break
    end
    job = pop_first(self.jobs)
    local sequence = self.execution_sequence
    self.execution_sequence = sequence + 1
    local ok, result, callback_error = pcall(job.callback, context(job, self.time_us, sequence))
    local error_value = nil
    if not ok then
      error_value = callback_failure(job, result)
    elseif result == nil and Errors.is(callback_error) then
      error_value = callback_failure(job, callback_error)
    end
    if error_value then
      finish(job, "failed", error_value)
      failures[#failures + 1] = { error = copy_error(error_value), job_id = job.id }
    else
      finish(job, "completed")
    end
    executed = executed + 1
  end
  self.advancing = false
  local due = self.jobs[1] and self.jobs[1].due_us <= self.time_us or false
  return {
    callback_budget_exhausted = due,
    executed = executed,
    failures = failures,
    logical_time_us = self.time_us,
  }
end

function scheduler_mt:status()
  return {
    active_jobs = #self.jobs,
    destroyed = self.destroyed,
    limits = copy_limits(self.limits),
    logical_time_us = self.time_us,
  }
end

function scheduler_mt:destroy()
  if self.destroyed then
    return true
  end
  while #self.jobs > 0 do
    finish(pop_first(self.jobs), "cancelled")
  end
  self.destroyed = true
  return true
end

return Scheduler
