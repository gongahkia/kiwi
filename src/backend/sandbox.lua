local Errors = require("runtime.errors")
local Event = require("runtime.event")
local Session = require("shell.session")

local Sandbox = {}
local sandbox_mt = {}
sandbox_mt.__index = sandbox_mt

Sandbox.contract = {
  complete = "complete(bytes, cursor_offset) -> completion_result | nil, error",
  constructor = "new(registry, config?) -> sandbox_backend | nil, error",
  history = "history() -> command_history",
  start = "start() -> true | nil, error",
  poll = "poll(advance_us) -> ordered_events | nil, error",
  send_input = "send_input(bytes) -> command_dispatch | nil, error",
  resize = "resize(columns, rows, pixel_width?, pixel_height?) -> true | nil, error",
  stop = "stop(reason?) -> true | nil, error",
  capabilities = "capabilities() -> sandbox_backend_capabilities",
  status = "status() -> sandbox_backend_status",
}

local default_limits = {
  max_active_invocations = 32,
  max_events_per_poll = 32,
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function unavailable(message, detail)
  return nil, Errors.new("backend_unavailable", message, detail)
end

local function exited(message, detail)
  return nil, Errors.new("backend_exited", message, detail)
end

local function resource_limit(message, detail)
  detail = detail or {}
  detail.reason = "resource_limit"
  return nil, Errors.new("sandbox_command_error", message, detail)
end

local function positive_limit(value, name, maximum)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 1 or value > maximum then
    return config_error(name .. " must be a positive bounded integer", {
      limit = maximum,
      minimum = 1,
      provided = value,
    })
  end
  return value
end

local function options(value)
  if value == nil then
    value = {}
  end
  if type(value) ~= "table" then
    return config_error("sandbox backend configuration must be a table")
  end
  for name in pairs(value) do
    if name ~= "max_active_invocations" and name ~= "max_events_per_poll" and name ~= "session" then
      return config_error("sandbox backend configuration option is unsupported", { option = name })
    end
  end
  local max_active_invocations, active_error = positive_limit(
    value.max_active_invocations or default_limits.max_active_invocations,
    "sandbox backend maximum active invocations",
    default_limits.max_active_invocations
  )
  if not max_active_invocations then
    return nil, active_error
  end
  local max_events_per_poll, events_error = positive_limit(
    value.max_events_per_poll or default_limits.max_events_per_poll,
    "sandbox backend maximum events per poll",
    default_limits.max_events_per_poll
  )
  if not max_events_per_poll then
    return nil, events_error
  end
  if value.session ~= nil and type(value.session) ~= "table" then
    return config_error("sandbox backend session configuration must be a table")
  end
  return {
    max_active_invocations = max_active_invocations,
    max_events_per_poll = max_events_per_poll,
    session = value.session,
  }
end

local function state_error(backend)
  if backend.state == "stopped" then
    return exited("sandbox backend is stopped", { reason = backend.stop_reason })
  end
  if backend.state == "idle" then
    return unavailable("sandbox backend has not started")
  end
  return true
end

local function release_settled(backend)
  local index = 1
  while index <= #backend.invocations do
    local invocation = backend.invocations[index]
    if invocation:status().settled then
      invocation:release()
      table.remove(backend.invocations, index)
    else
      index = index + 1
    end
  end
end

local function queue_resize(backend, columns, rows, pixel_width, pixel_height)
  if #backend.pending_resizes >= backend.max_events_per_poll then
    return resource_limit("sandbox backend resize queue is full", {
      limit = backend.max_events_per_poll,
      pending_resizes = #backend.pending_resizes,
    })
  end
  local event, event_error = Event.resize(columns, rows, pixel_width, pixel_height, 0)
  if not event then
    return nil, event_error
  end
  backend.pending_resizes[#backend.pending_resizes + 1] = event
  return true
end

function Sandbox.new(registry, configuration)
  if type(registry) ~= "table" or type(registry.command) ~= "function" then
    return config_error("sandbox backend requires a command registry")
  end
  local settings, settings_error = options(configuration)
  if not settings then
    return nil, settings_error
  end
  local session, session_error = Session.new(registry, settings.session)
  if not session then
    return nil, session_error
  end
  return setmetatable({
    invocations = {},
    max_active_invocations = settings.max_active_invocations,
    max_events_per_poll = settings.max_events_per_poll,
    pending_resizes = {},
    registry = registry,
    session = session,
    state = "idle",
    stop_reason = nil,
  }, sandbox_mt)
end

function sandbox_mt:start()
  if self.state == "stopped" then
    return exited("stopped sandbox backends cannot restart")
  end
  self.state = "running"
  return true
end

function sandbox_mt:send_input(bytes)
  local valid, valid_error = state_error(self)
  if not valid then
    return nil, valid_error
  end
  release_settled(self)
  if #self.invocations >= self.max_active_invocations then
    return resource_limit("sandbox backend has too many active invocations", {
      active_invocations = #self.invocations,
      limit = self.max_active_invocations,
    })
  end
  local outcome, dispatch_error = self.session:dispatch(bytes)
  if not outcome then
    return nil, dispatch_error
  end
  if outcome.dispatched and not outcome.invocation:status().settled then
    self.invocations[#self.invocations + 1] = outcome.invocation
  elseif outcome.dispatched then
    outcome.invocation:release()
  end
  return outcome
end

function sandbox_mt:poll(advance_us)
  local valid, valid_error = state_error(self)
  if not valid then
    return nil, valid_error
  end
  local advanced, advance_error = self.session:advance(advance_us)
  if not advanced then
    return nil, advance_error
  end
  local events = {}
  local resize_index = 1
  while resize_index <= #self.pending_resizes and #events < self.max_events_per_poll do
    events[#events + 1] = self.pending_resizes[resize_index]
    resize_index = resize_index + 1
  end
  if resize_index > 1 then
    local remaining = {}
    for index = resize_index, #self.pending_resizes do
      remaining[#remaining + 1] = self.pending_resizes[index]
    end
    self.pending_resizes = remaining
  end
  local invocation_index = 1
  while invocation_index <= #self.invocations and #events < self.max_events_per_poll do
    local invocation = self.invocations[invocation_index]
    if invocation:status().queued_chunks > 0 then
      local limits = invocation:limits()
      local result, poll_error = invocation:poll({
        max_bytes = limits.max_drain_bytes,
        max_events = math.min(self.max_events_per_poll - #events, limits.max_output_events),
      })
      if not result then
        return nil, poll_error
      end
      for _, event in ipairs(result.events) do
        if #events >= self.max_events_per_poll then
          break
        end
        events[#events + 1] = event
      end
    end
    invocation_index = invocation_index + 1
  end
  release_settled(self)
  return events
end

function sandbox_mt:resize(columns, rows, pixel_width, pixel_height)
  local valid, valid_error = state_error(self)
  if not valid then
    return nil, valid_error
  end
  return queue_resize(self, columns, rows, pixel_width, pixel_height)
end

function sandbox_mt:complete(bytes, cursor_offset)
  local valid, valid_error = state_error(self)
  if not valid then
    return nil, valid_error
  end
  return self.session:complete(bytes, cursor_offset)
end

function sandbox_mt:history()
  return self.session:history()
end

function sandbox_mt:stop(reason)
  if self.state == "stopped" then
    return true
  end
  self.stop_reason = reason or "stopped"
  for _, invocation in ipairs(self.invocations) do
    invocation:cancel()
  end
  self.invocations = {}
  self.pending_resizes = {}
  self.session:destroy()
  self.state = "stopped"
  return true
end

function sandbox_mt:capabilities()
  return {
    completion = true,
    deterministic_time = true,
    input = true,
    pause = false,
    resize = true,
    sandbox_commands = true,
    seek = false,
  }
end

function sandbox_mt:status()
  return {
    active_invocations = #self.invocations,
    max_active_invocations = self.max_active_invocations,
    max_events_per_poll = self.max_events_per_poll,
    pending_resizes = #self.pending_resizes,
    session = self.session:status(),
    state = self.state,
  }
end

return Sandbox
