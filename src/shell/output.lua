local Errors = require("runtime.errors")
local Event = require("runtime.event")

local Output = {}

Output.contract = {
  new = "new(limits?, next_sequence?, on_cancel?) -> command_output_invocation | nil, error",
  normalise_limits = "normalise_limits(limits?) -> command_output_limits | nil, error",
}

local MAX_U32 = 4294967295
local default_limits = {
  max_drain_bytes = 16384,
  max_output_events = 16,
  max_queued_bytes = 65536,
  max_queued_chunks = 64,
  max_write_bytes = 16384,
}

local allowed_limits = {
  max_drain_bytes = true,
  max_output_events = true,
  max_queued_bytes = true,
  max_queued_chunks = true,
  max_write_bytes = true,
}

local function command_error(message, detail)
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function failure(reason, message, detail)
  detail = detail or {}
  detail.reason = reason
  local _, error_value = command_error(message, detail)
  return error_value
end

local function limit(value, name, default)
  if value == nil then
    return default
  end
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > default then
    return command_error(name .. " must be an integer within the supported bound", {
      limit = default,
      minimum = 1,
      provided = value,
    })
  end
  return value
end

function Output.normalise_limits(limits)
  if limits == nil then
    limits = {}
  end
  if type(limits) ~= "table" then
    return command_error("sandbox output limits must be a table", { reason = "invalid_limits" })
  end
  local has_unsupported_limit = false
  for name in pairs(limits) do
    if not allowed_limits[name] then
      has_unsupported_limit = true
    end
  end
  if has_unsupported_limit then
    return command_error("sandbox output limit is unsupported", { reason = "invalid_limits" })
  end
  local max_write_bytes, write_error = limit(
    limits.max_write_bytes,
    "sandbox output maximum write bytes",
    default_limits.max_write_bytes
  )
  if not max_write_bytes then
    return nil, write_error
  end
  local max_queued_bytes, bytes_error = limit(
    limits.max_queued_bytes,
    "sandbox output maximum queued bytes",
    default_limits.max_queued_bytes
  )
  if not max_queued_bytes then
    return nil, bytes_error
  end
  local max_queued_chunks, chunks_error = limit(
    limits.max_queued_chunks,
    "sandbox output maximum queued chunks",
    default_limits.max_queued_chunks
  )
  if not max_queued_chunks then
    return nil, chunks_error
  end
  local max_drain_bytes, drain_error = limit(
    limits.max_drain_bytes,
    "sandbox output maximum drain bytes",
    default_limits.max_drain_bytes
  )
  if not max_drain_bytes then
    return nil, drain_error
  end
  local max_output_events, events_error = limit(
    limits.max_output_events,
    "sandbox output maximum events",
    default_limits.max_output_events
  )
  if not max_output_events then
    return nil, events_error
  end
  if max_write_bytes > max_queued_bytes then
    return command_error("sandbox output write limit exceeds queued byte limit", {
      max_queued_bytes = max_queued_bytes,
      max_write_bytes = max_write_bytes,
    })
  end
  return {
    max_drain_bytes = max_drain_bytes,
    max_output_events = max_output_events,
    max_queued_bytes = max_queued_bytes,
    max_queued_chunks = max_queued_chunks,
    max_write_bytes = max_write_bytes,
  }
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

local function copy_limits(limits)
  return {
    max_drain_bytes = limits.max_drain_bytes,
    max_output_events = limits.max_output_events,
    max_queued_bytes = limits.max_queued_bytes,
    max_queued_chunks = limits.max_queued_chunks,
    max_write_bytes = limits.max_write_bytes,
  }
end

local function poll_limits(value, limits)
  if value == nil then
    return {
      max_bytes = limits.max_drain_bytes,
      max_events = limits.max_output_events,
    }
  end
  if type(value) ~= "table" then
    return command_error("sandbox output poll limits must be a table", {
      reason = "invalid_poll_limit",
    })
  end
  local has_unsupported_limit = false
  for name in pairs(value) do
    if name ~= "max_bytes" and name ~= "max_events" then
      has_unsupported_limit = true
    end
  end
  if has_unsupported_limit then
    return command_error("sandbox output poll limit is unsupported", {
      reason = "invalid_poll_limit",
    })
  end
  local max_bytes = value.max_bytes or limits.max_drain_bytes
  if
    type(max_bytes) ~= "number"
    or max_bytes % 1 ~= 0
    or max_bytes < 1
    or max_bytes > limits.max_drain_bytes
  then
    return command_error("sandbox output poll byte limit is invalid", {
      limit = limits.max_drain_bytes,
      provided = max_bytes,
      reason = "invalid_poll_limit",
    })
  end
  local max_events = value.max_events or limits.max_output_events
  if
    type(max_events) ~= "number"
    or max_events % 1 ~= 0
    or max_events < 1
    or max_events > limits.max_output_events
  then
    return command_error("sandbox output poll event limit is invalid", {
      limit = limits.max_output_events,
      provided = max_events,
      reason = "invalid_poll_limit",
    })
  end
  return { max_bytes = max_bytes, max_events = max_events }
end

local function next_sequence_factory(next_sequence)
  if next_sequence ~= nil then
    if type(next_sequence) ~= "function" then
      return command_error("sandbox output sequence source must be a function")
    end
    return next_sequence
  end
  local sequence = 1
  return function()
    if sequence > MAX_U32 then
      return nil
    end
    local result = sequence
    sequence = sequence + 1
    return result
  end
end

function Output.new(configuration, next_sequence, on_cancel)
  local limits, limits_error = Output.normalise_limits(configuration)
  if not limits then
    return nil, limits_error
  end
  local sequence_source, sequence_error = next_sequence_factory(next_sequence)
  if not sequence_source then
    return nil, sequence_error
  end
  if on_cancel ~= nil and type(on_cancel) ~= "function" then
    return command_error("sandbox output cancellation callback must be a function", {
      reason = "output_resource_limit",
    })
  end

  local execution_state = "running"
  local failure_value = nil
  local completion_requested = false
  local pending_work = 0
  local queue = {}
  local queue_head = 1
  local queue_tail = 1
  local queued_bytes = 0
  local queued_chunks = 0
  local released = false

  local function empty_queue()
    queue = {}
    queue_head = 1
    queue_tail = 1
    queued_bytes = 0
    queued_chunks = 0
  end

  local function closed_error()
    local _, error_value =
      command_error("sandbox output writer is closed", { reason = "output_closed" })
    return error_value
  end

  local function settled()
    return execution_state ~= "running" and pending_work == 0 and queued_chunks == 0
  end

  local function finish_if_ready()
    if completion_requested and pending_work == 0 and execution_state == "running" then
      execution_state = failure_value and "failed" or "finished"
    end
  end

  local function status()
    local state = execution_state
    if execution_state == "finished" and queued_chunks > 0 then
      state = "finished_with_output"
    elseif execution_state == "failed" and queued_chunks > 0 then
      state = "failed_with_output"
    elseif execution_state == "finished" and queued_chunks == 0 then
      state = "settled"
    end
    return {
      execution_state = execution_state,
      failed = failure_value ~= nil,
      failure = copy_error(failure_value),
      queued_bytes = queued_bytes,
      queued_chunks = queued_chunks,
      pending_work = pending_work,
      released = released,
      settled = settled(),
      state = state,
    }
  end

  local function close_with_failure(error_value)
    if failure_value == nil then
      failure_value = error_value
    end
  end

  local writer = {}
  local writer_methods = {}

  function writer_methods:emit(bytes)
    if released or execution_state ~= "running" or failure_value ~= nil then
      return nil, closed_error()
    end
    if type(bytes) ~= "string" then
      return command_error(
        "sandbox output bytes must be a byte string",
        { reason = "invalid_output" }
      )
    end
    if #bytes == 0 then
      return true
    end
    if #bytes > limits.max_write_bytes then
      local error_value = failure("emit_too_large", "sandbox output write exceeds its byte limit", {
        attempted_write_bytes = #bytes,
        limit = limits.max_write_bytes,
      })
      close_with_failure(failure("output_overflow", "sandbox output queue overflow", {
        attempted_write_bytes = #bytes,
        max_queued_bytes = limits.max_queued_bytes,
        max_queued_chunks = limits.max_queued_chunks,
        queued_bytes = queued_bytes,
        queued_chunks = queued_chunks,
      }))
      return nil, error_value
    end
    if
      queued_bytes + #bytes > limits.max_queued_bytes or queued_chunks >= limits.max_queued_chunks
    then
      local error_value = failure("output_overflow", "sandbox output queue overflow", {
        attempted_write_bytes = #bytes,
        max_queued_bytes = limits.max_queued_bytes,
        max_queued_chunks = limits.max_queued_chunks,
        queued_bytes = queued_bytes,
        queued_chunks = queued_chunks,
      })
      close_with_failure(error_value)
      return nil, error_value
    end
    queue[queue_tail] = bytes:sub(1, #bytes)
    queue_tail = queue_tail % limits.max_queued_chunks + 1
    queued_bytes = queued_bytes + #bytes
    queued_chunks = queued_chunks + 1
    return true
  end

  setmetatable(writer, {
    __index = writer_methods,
    __metatable = false,
    __newindex = function(_, key)
      error("sandbox output writer is immutable: " .. tostring(key), 2)
    end,
  })

  local invocation = {}
  local methods = {}

  function methods:writer()
    return writer
  end

  function methods:limits()
    return copy_limits(limits)
  end

  function methods:status()
    return status()
  end

  function methods:complete()
    completion_requested = true
    finish_if_ready()
    return true
  end

  function methods:hold()
    if released or execution_state ~= "running" then
      return command_error("sandbox output invocation is closed", { reason = "output_closed" })
    end
    pending_work = pending_work + 1
    return true
  end

  function methods:release_hold()
    if pending_work == 0 then
      return command_error("sandbox output invocation has no retained work", {
        reason = "output_resource_limit",
      })
    end
    pending_work = pending_work - 1
    finish_if_ready()
    return true
  end

  function methods:fail(error_value)
    if execution_state == "running" then
      close_with_failure(error_value)
      execution_state = "failed"
    end
    return true
  end

  function methods:cancel()
    if released or settled() then
      return true
    end
    if execution_state ~= "cancelled" then
      close_with_failure(failure("cancelled", "sandbox output invocation was cancelled"))
      execution_state = "cancelled"
      if on_cancel then
        pcall(on_cancel)
      end
    end
    return true
  end

  function methods:poll(requested_limits)
    local requested, requested_error = poll_limits(requested_limits, limits)
    if not requested then
      return nil, requested_error
    end
    if released or queued_chunks == 0 then
      return { events = {}, status = status() }
    end
    local sequence = sequence_source()
    if type(sequence) ~= "number" or sequence % 1 ~= 0 or sequence < 0 or sequence > MAX_U32 then
      return command_error("sandbox output event sequence is exhausted", {
        reason = "output_resource_limit",
      })
    end
    local remaining = requested.max_bytes
    local chunks = {}
    while remaining > 0 and queued_chunks > 0 do
      local head = queue[queue_head]
      local take = math.min(#head, remaining)
      chunks[#chunks + 1] = head:sub(1, take)
      queued_bytes = queued_bytes - take
      remaining = remaining - take
      if take == #head then
        queue[queue_head] = nil
        queue_head = queue_head % limits.max_queued_chunks + 1
        queued_chunks = queued_chunks - 1
      else
        queue[queue_head] = head:sub(take + 1)
      end
    end
    local output = table.concat(chunks)
    local event, event_error = Event.output(output, 0, sequence)
    if not event then
      return nil, event_error
    end
    if queued_chunks == 0 then
      empty_queue()
    end
    return { events = { event }, status = status() }
  end

  function methods:release()
    if released then
      return true
    end
    if not settled() then
      return command_error("sandbox output invocation is not settled", {
        reason = "output_resource_limit",
      })
    end
    empty_queue()
    released = true
    return true
  end

  return setmetatable(invocation, {
    __index = methods,
    __metatable = false,
    __newindex = function(_, key)
      error("sandbox output invocation is immutable: " .. tostring(key), 2)
    end,
  })
end

return Output
