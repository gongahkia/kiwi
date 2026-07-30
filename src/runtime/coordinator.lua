local Backend = require("backend.interface")
local Errors = require("runtime.errors")
local Event = require("runtime.event")

local Coordinator = {}
local coordinator_mt = {}
coordinator_mt.__index = coordinator_mt

Coordinator.contract = {
  constructor = "new(terminal, backend, options?) -> coordinator | nil, error",
  start = "start() -> true | nil, error",
  seek = "seek(target_terminal_us) -> applied_events | nil, error",
  step_control_sequence = "step_control_sequence() -> step | nil, error?",
  step_frame = "step_frame() -> step | nil, error?",
  stop = "stop(reason?) -> true | nil, error",
  update = "update(advance_us) -> applied_events | nil, error",
}

local boundary_kinds = {
  control = true,
  csi = true,
  esc = true,
  malformed = true,
  osc = true,
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function positive_integer(value, name)
  if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 1 then
    return config_error(name .. " must be a positive integer", { provided = value })
  end
  return value
end

local function options(value)
  if value == nil then
    value = {}
  end
  if type(value) ~= "table" then
    return config_error("coordinator options must be a table")
  end
  for name in pairs(value) do
    if name ~= "max_backend_events_per_update" then
      return config_error("unknown coordinator option", { option = name })
    end
  end
  return positive_integer(
    value.max_backend_events_per_update or 1024,
    "coordinator max backend events per update"
  )
end

local function unavailable(message)
  return nil, Errors.new("backend_unavailable", message)
end

local function valid_terminal(terminal)
  if type(terminal) ~= "table" or type(terminal.feed_output) ~= "function" then
    return nil, Errors.new("config_error", "coordinator terminal must implement feed_output")
  end
  if type(terminal.resize) ~= "function" then
    return nil, Errors.new("config_error", "coordinator terminal must implement resize")
  end
  return terminal
end

local function prepare_event(coordinator, event)
  local normalised, event_error = Event.validate(event)
  if not normalised then
    return nil, event_error
  end
  if coordinator.event_sequence >= 0xFFFFFFFF then
    return nil, Errors.new("backend_protocol_error", "coordinator event sequence is exhausted")
  end
  coordinator.event_sequence = coordinator.event_sequence + 1
  normalised.source_sequence = coordinator.event_sequence
  coordinator.terminal_time_us = coordinator.terminal_time_us + normalised.delta_us
  return normalised
end

local function apply_prepared_event(coordinator, event)
  local semantic_events = {}
  local parser_events = {}
  if event.kind == "output" then
    semantic_events, parser_events = coordinator.terminal:feed_output(event.data)
    if not semantic_events then
      return nil, parser_events
    end
  elseif event.kind == "resize" then
    local resized, resize_error = coordinator.terminal:resize(event.columns, event.rows)
    if not resized then
      return nil, resize_error
    end
  end
  return {
    event = event,
    parser_events = parser_events,
    semantic_events = semantic_events,
  }
end

local function apply_event(coordinator, event)
  local prepared, prepare_error = prepare_event(coordinator, event)
  if not prepared then
    return nil, prepare_error
  end
  return apply_prepared_event(coordinator, prepared)
end

local function step_backend_frame(coordinator)
  if type(coordinator.backend.step_frame) ~= "function" then
    return unavailable("backend does not support frame stepping")
  end
  return coordinator.backend:step_frame()
end

local function append_events(target, source)
  for _, event in ipairs(source) do
    target[#target + 1] = event
  end
end

local function boundary(parser_events)
  for _, parser_event in ipairs(parser_events) do
    if boundary_kinds[parser_event.kind] then
      return parser_event
    end
  end
  return nil
end

function Coordinator.new(terminal, backend, configuration)
  local valid_terminal_value, terminal_error = valid_terminal(terminal)
  if not valid_terminal_value then
    return nil, terminal_error
  end
  local valid_backend, backend_error = Backend.validate(backend)
  if not valid_backend then
    return nil, backend_error
  end
  local max_backend_events_per_update, options_error = options(configuration)
  if not max_backend_events_per_update then
    return nil, options_error
  end
  return setmetatable({
    backend = valid_backend,
    event_sequence = 0,
    max_backend_events_per_update = max_backend_events_per_update,
    pending_backend_events = nil,
    pending_backend_index = nil,
    pending_output = nil,
    started = false,
    stopped = false,
    terminal = valid_terminal_value,
    terminal_time_us = 0,
  }, coordinator_mt)
end

function coordinator_mt:start()
  if self.stopped then
    return nil, Errors.new("backend_exited", "coordinator is stopped")
  end
  if self.started then
    return true
  end
  local started, start_error = self.backend:start()
  if not started then
    return nil, start_error
  end
  self.started = true
  return true
end

function coordinator_mt:update(advance_us)
  if self.pending_output then
    return config_error("cannot update while a control-sequence step has pending output")
  end
  local started, start_error = self:start()
  if not started then
    return nil, start_error
  end
  if self.pending_backend_events == nil then
    local events, poll_error = self.backend:poll(advance_us)
    if not events then
      return nil, poll_error
    end
    self.pending_backend_events = events
    self.pending_backend_index = 1
  end
  local applied = {}
  while
    #applied < self.max_backend_events_per_update
    and self.pending_backend_index <= #self.pending_backend_events
  do
    local event = self.pending_backend_events[self.pending_backend_index]
    local result, apply_error = apply_event(self, event)
    if not result then
      return nil, apply_error
    end
    applied[#applied + 1] = result
    self.pending_backend_index = self.pending_backend_index + 1
  end
  if self.pending_backend_index > #self.pending_backend_events then
    self.pending_backend_events = nil
    self.pending_backend_index = nil
  end
  return applied
end

function coordinator_mt:step_frame()
  if self.pending_output then
    return config_error("cannot step a frame while a control-sequence step has pending output")
  end
  if self.pending_backend_events then
    return config_error("cannot step a frame while update backlog is pending")
  end
  local started, start_error = self:start()
  if not started then
    return nil, start_error
  end
  local step, step_error = step_backend_frame(self)
  if not step then
    return nil, step_error
  end
  local result = { frame = step.frame, frame_index = step.frame_index }
  if step.event then
    local applied, apply_error = apply_event(self, step.event)
    if not applied then
      return nil, apply_error
    end
    result.applied = applied
  end
  return result
end

function coordinator_mt:step_control_sequence()
  if self.pending_backend_events then
    return config_error("cannot step a control sequence while update backlog is pending")
  end
  local started, start_error = self:start()
  if not started then
    return nil, start_error
  end
  if not self.pending_output then
    local step, step_error = step_backend_frame(self)
    if not step then
      return nil, step_error
    end
    if not step.event or step.event.kind ~= "output" then
      local result = { frame = step.frame, frame_index = step.frame_index, kind = "frame" }
      if step.event then
        local applied, apply_error = apply_event(self, step.event)
        if not applied then
          return nil, apply_error
        end
        result.applied = applied
      end
      return result
    end
    local event, event_error = prepare_event(self, step.event)
    if not event then
      return nil, event_error
    end
    self.pending_output = {
      event = event,
      frame = step.frame,
      frame_index = step.frame_index,
      index = 1,
    }
  end
  local pending = self.pending_output
  local parser_events = {}
  local semantic_events = {}
  local start_index = pending.index
  local found_boundary
  while pending.index <= #pending.event.data do
    local byte = pending.event.data:sub(pending.index, pending.index)
    pending.index = pending.index + 1
    local semantic, parser = self.terminal:feed_output(byte)
    if not semantic then
      return nil, parser
    end
    append_events(semantic_events, semantic)
    append_events(parser_events, parser)
    found_boundary = boundary(parser)
    if found_boundary then
      break
    end
  end
  local completed = pending.index > #pending.event.data
  if completed then
    self.pending_output = nil
  end
  return {
    boundary = found_boundary,
    bytes = pending.index - start_index,
    completed_frame = completed,
    event = pending.event,
    frame = pending.frame,
    frame_index = pending.frame_index,
    kind = found_boundary and "control_sequence" or "output_frame",
    parser_events = parser_events,
    semantic_events = semantic_events,
  }
end

function coordinator_mt:seek(target_terminal_us)
  if self.pending_output then
    return config_error("cannot seek while a control-sequence step has pending output")
  end
  local started, start_error = self:start()
  if not started then
    return nil, start_error
  end
  if type(self.backend.seek) ~= "function" then
    return unavailable("backend does not support seek")
  end
  local plan, seek_error = self.backend:seek(target_terminal_us)
  if not plan then
    return nil, seek_error
  end
  self.terminal = plan.terminal
  self.pending_backend_events = nil
  self.pending_backend_index = nil
  self.terminal_time_us = plan.checkpoint_terminal_us
  self.event_sequence = plan.frame_index
  local resumed, resume_error = self.backend:resume()
  if not resumed then
    return nil, resume_error
  end
  local applied = {}
  while true do
    local batch, update_error = self:update(0)
    if not batch then
      return nil, update_error
    end
    append_events(applied, batch)
    if #batch == 0 then
      break
    end
  end
  local paused, pause_error = self.backend:pause()
  if not paused and self.backend:status().state ~= "exhausted" then
    return nil, pause_error
  end
  return applied
end

function coordinator_mt:terminal_instance()
  return self.terminal
end

function coordinator_mt:stop(reason)
  if self.stopped then
    return true
  end
  self.stopped = true
  self.pending_backend_events = nil
  self.pending_backend_index = nil
  self.pending_output = nil
  return self.backend:stop(reason)
end

function coordinator_mt:status()
  local pending_backend_events = 0
  if self.pending_backend_events then
    pending_backend_events = #self.pending_backend_events - self.pending_backend_index + 1
  end
  return {
    event_sequence = self.event_sequence,
    max_backend_events_per_update = self.max_backend_events_per_update,
    pending_backend_events = pending_backend_events,
    pending_output = self.pending_output ~= nil,
    started = self.started,
    stopped = self.stopped,
    terminal_time_us = self.terminal_time_us,
  }
end

return Coordinator
