local Errors = require("runtime.errors")
local Frames = require("recording.frames")
local RecordingReader = require("recording.reader")

local Replay = {}
local replay_mt = {}
replay_mt.__index = replay_mt

Replay.contract = {
  constructor = "new(source, config?) -> replay_backend | nil, error",
  pause = "pause() -> true | nil, error",
  marks = "marks() -> bookmark_descriptors | nil, error",
  play = "play() -> true | nil, error",
  resume = "resume() -> true | nil, error",
  seek = "seek(target_terminal_us) -> checkpoint_plan | nil, error",
  seek_mark = "seek_mark(name, occurrence?) -> checkpoint_plan | nil, error",
  set_speed = "set_speed(multiplier) -> true | nil, error",
  step_frame = "step_frame() -> step | nil, error?",
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

local function uint32(value, name)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 0xFFFFFFFF then
    return config_error(name .. " must be an unsigned 32-bit integer", { provided = value })
  end
  return value
end

local function positive_number(value, name)
  if type(value) ~= "number" or value ~= value or value <= 0 or value == math.huge then
    return config_error(name .. " must be a positive finite number", { provided = value })
  end
  return value
end

local function config_for(config)
  if config == nil then
    config = {}
  end
  if type(config) ~= "table" then
    return config_error("replay configuration must be a table")
  end
  local speed, speed_error = positive_number(config.speed or 1, "replay speed")
  if not speed then
    return nil, speed_error
  end
  local max_events, events_error =
    uint32(config.max_events_per_poll or 1024, "maximum events per poll")
  if not max_events or max_events == 0 then
    return nil,
      events_error or Errors.new("config_error", "maximum events per poll must be positive")
  end
  local reader_limits = config.reader_limits
  if reader_limits ~= nil and type(reader_limits) ~= "table" then
    return config_error("replay reader limits must be a table")
  end
  local max_checkpoint_entries, checkpoints_error =
    uint32(config.max_checkpoint_entries or 1024, "maximum checkpoint index entries")
  if not max_checkpoint_entries or max_checkpoint_entries < 2 then
    return nil,
      checkpoints_error or Errors.new(
        "config_error",
        "maximum checkpoint index entries must be at least two"
      )
  end
  local max_mark_entries, marks_error =
    uint32(config.max_mark_entries or 1024, "maximum mark entries")
  if not max_mark_entries or max_mark_entries < 2 then
    return nil,
      marks_error or Errors.new("config_error", "maximum mark entries must be at least two")
  end
  return {
    max_checkpoint_entries = max_checkpoint_entries,
    max_mark_entries = max_mark_entries,
    max_events_per_poll = max_events,
    reader_limits = reader_limits,
    speed = speed,
  }
end

local fail

local function add_checkpoint_index_entry(replay, entry)
  local entries = replay.checkpoint_index
  entries[#entries + 1] = entry
  while #entries > replay.config.max_checkpoint_entries do
    replay.checkpoint_stride = replay.checkpoint_stride * 2
    local compacted = { entries[1] }
    for index = 2, #entries do
      local candidate = entries[index]
      if candidate.ordinal % replay.checkpoint_stride == 0 or index == #entries then
        if compacted[#compacted] ~= candidate then
          compacted[#compacted + 1] = candidate
        end
      end
    end
    replay.checkpoint_index = compacted
    entries = compacted
  end
end

local function add_mark_index_entry(replay, entry)
  local entries = replay.mark_index
  entries[#entries + 1] = entry
  while #entries > replay.config.max_mark_entries do
    replay.mark_stride = replay.mark_stride * 2
    local compacted = { entries[1] }
    for index = 2, #entries do
      local candidate = entries[index]
      if candidate.ordinal % replay.mark_stride == 0 or index == #entries then
        if compacted[#compacted] ~= candidate then
          compacted[#compacted + 1] = candidate
        end
      end
    end
    replay.mark_index = compacted
    entries = compacted
  end
end

local function build_index(replay)
  if replay.index_state == "ready" then
    return true
  end
  if type(replay.reader.source.seek) ~= "function" then
    replay.index_state = "unavailable"
    return true
  end
  local first_frame_offset, position_error = replay.reader:position()
  if not first_frame_offset then
    return fail(replay, position_error)
  end
  local rewound, rewind_error = replay.reader:seek_frame(first_frame_offset)
  if not rewound then
    return fail(replay, rewind_error)
  end
  replay.checkpoint_index = {}
  replay.checkpoint_count = 0
  replay.checkpoint_stride = 1
  replay.mark_index = {}
  replay.mark_count = 0
  replay.mark_stride = 1
  local elapsed_terminal_us = 0
  local frame_index = 0
  while true do
    local frame_offset, offset_error = replay.reader:position()
    if not frame_offset then
      return fail(replay, offset_error)
    end
    local frame, frame_error = replay.reader:read_next()
    if not frame then
      if frame_error then
        return fail(replay, frame_error)
      end
      break
    end
    frame_index = frame_index + 1
    elapsed_terminal_us = elapsed_terminal_us + frame.delta_us
    if frame.kind == 0x05 then
      local restored, checkpoint_error =
        Frames.restore_checkpoint(frame, replay.config.reader_limits)
      if not restored then
        return fail(replay, checkpoint_error)
      end
      replay.checkpoint_count = replay.checkpoint_count + 1
      add_checkpoint_index_entry(replay, {
        elapsed_terminal_us = elapsed_terminal_us,
        frame_index = frame_index,
        offset = frame_offset,
        ordinal = replay.checkpoint_count,
      })
    elseif frame.kind == 0x04 then
      local mark, mark_error = Frames.to_event(frame)
      if not mark then
        return fail(replay, mark_error)
      end
      replay.mark_count = replay.mark_count + 1
      add_mark_index_entry(replay, {
        frame_index = frame_index,
        name = mark.name,
        ordinal = replay.mark_count,
        terminal_us = elapsed_terminal_us,
      })
    end
  end
  local reset, reset_error = replay.reader:seek_frame(first_frame_offset)
  if not reset then
    return fail(replay, reset_error)
  end
  replay.index_state = "ready"
  replay.total_duration_us = elapsed_terminal_us
  return true
end

local function state_error(replay)
  if replay.state == "stopped" then
    return exited("replay backend is stopped", { reason = replay.stop_reason })
  end
  if replay.state == "failed" then
    return nil, replay.failure
  end
  if replay.state == "idle" then
    return unavailable("replay backend has not started")
  end
  return true
end

fail = function(replay, error_value)
  replay.failure = error_value
  replay.state = "failed"
  return nil, error_value
end

local function load_next(replay)
  if replay.next_frame or replay.ended then
    return true
  end
  local frame, frame_error = replay.reader:read_next()
  if not frame then
    if frame_error then
      return fail(replay, frame_error)
    end
    replay.ended = true
    replay.state = "exhausted"
    return true
  end
  replay.next_frame = frame
  return true
end

local function replayable_event(frame)
  local event, event_error = Frames.to_event(frame)
  if event then
    return event
  end
  if frame.kind == 0x05 or frame.kind == 0x06 or frame.kind == 0x07 then
    return nil
  end
  if frame.kind < 0x01 or frame.kind > 0x08 then
    return nil
  end
  return nil, event_error
end

local function consume_frame(replay, force)
  local loaded, load_error = load_next(replay)
  if not loaded then
    return nil, load_error
  end
  if replay.ended then
    return nil
  end
  local due_us = replay.elapsed_terminal_us + replay.next_frame.delta_us
  if not force and replay.playhead_us < due_us then
    return false
  end
  if force and replay.playhead_us < due_us then
    replay.playhead_us = due_us
  end
  local frame = replay.next_frame
  replay.next_frame = nil
  replay.current_frame = replay.current_frame + 1
  replay.elapsed_terminal_us = due_us
  local event, event_error = replayable_event(frame)
  if event_error then
    return fail(replay, event_error)
  end
  return {
    elapsed_terminal_us = replay.elapsed_terminal_us,
    event = event,
    frame = frame,
    frame_index = replay.current_frame,
  }
end

function Replay.new(source, config)
  local settings, settings_error = config_for(config)
  if not settings then
    return nil, settings_error
  end
  local reader, reader_error = RecordingReader.new(source, settings.reader_limits)
  if not reader then
    return nil, reader_error
  end
  return setmetatable({
    config = settings,
    current_frame = 0,
    checkpoint_count = 0,
    checkpoint_index = {},
    checkpoint_stride = 1,
    elapsed_terminal_us = 0,
    ended = false,
    failure = nil,
    next_frame = nil,
    mark_count = 0,
    mark_index = {},
    mark_stride = 1,
    playhead_us = 0,
    reader = reader,
    speed = settings.speed,
    state = "idle",
    stop_reason = nil,
    index_state = "unbuilt",
    total_duration_us = nil,
  }, replay_mt)
end

function replay_mt:start()
  if self.state == "stopped" then
    return exited("stopped replay backends cannot restart")
  end
  if self.state == "failed" then
    return nil, self.failure
  end
  local indexed, index_error = build_index(self)
  if not indexed then
    return nil, index_error
  end
  if self.state == "idle" then
    self.state = "playing"
  end
  return true
end

function replay_mt:play()
  return self:resume()
end

function replay_mt:pause()
  local valid, valid_error = state_error(self)
  if not valid then
    return nil, valid_error
  end
  if self.state == "exhausted" then
    return exited("replay backend is exhausted")
  end
  self.state = "paused"
  return true
end

function replay_mt:resume()
  if self.state == "idle" then
    return self:start()
  end
  local valid, valid_error = state_error(self)
  if not valid then
    return nil, valid_error
  end
  if self.state == "exhausted" then
    return exited("replay backend is exhausted")
  end
  self.state = "playing"
  return true
end

function replay_mt:set_speed(multiplier)
  local speed, speed_error = positive_number(multiplier, "replay speed")
  if not speed then
    return nil, speed_error
  end
  self.speed = speed
  return true
end

function replay_mt:step_frame()
  if self.state == "idle" then
    local started, start_error = self:start()
    if not started then
      return nil, start_error
    end
  end
  local valid, valid_error = state_error(self)
  if not valid then
    return nil, valid_error
  end
  if self.state == "exhausted" then
    return nil
  end
  self.state = "paused"
  return consume_frame(self, true)
end

function replay_mt:marks()
  if self.state == "idle" then
    local started, start_error = self:start()
    if not started then
      return nil, start_error
    end
  end
  local valid, valid_error = state_error(self)
  if not valid and self.state ~= "exhausted" then
    return nil, valid_error
  end
  if self.index_state ~= "ready" then
    return unavailable("replay bookmark listing requires a seekable recording source")
  end
  local marks = {}
  for index, mark in ipairs(self.mark_index) do
    marks[index] = {
      frame_index = mark.frame_index,
      name = mark.name,
      terminal_us = mark.terminal_us,
    }
  end
  return marks
end

function replay_mt:seek(target_terminal_us)
  if self.state == "idle" then
    local started, start_error = self:start()
    if not started then
      return nil, start_error
    end
  end
  local valid, valid_error = state_error(self)
  if not valid and self.state ~= "exhausted" then
    return nil, valid_error
  end
  local target, target_error = uint32(target_terminal_us, "replay seek target")
  if not target then
    return nil, target_error
  end
  if self.index_state ~= "ready" then
    return unavailable("replay seeking requires a seekable recording source")
  end
  if target > self.total_duration_us then
    return config_error("replay seek target exceeds recording duration", {
      duration_us = self.total_duration_us,
      provided = target,
    })
  end
  local selected
  for _, entry in ipairs(self.checkpoint_index) do
    if entry.elapsed_terminal_us <= target then
      selected = entry
    else
      break
    end
  end
  if not selected then
    return unavailable("replay seek target has no indexed checkpoint")
  end
  local positioned, position_error = self.reader:seek_frame(selected.offset)
  if not positioned then
    return fail(self, position_error)
  end
  local frame, frame_error = self.reader:read_next()
  if not frame then
    return fail(
      self,
      frame_error or Errors.new("recording_corrupt", "indexed checkpoint is truncated")
    )
  end
  if frame.kind ~= 0x05 then
    return fail(
      self,
      Errors.new("internal_invariant_error", "checkpoint index points to another frame")
    )
  end
  local terminal, checkpoint_error = Frames.restore_checkpoint(frame, self.config.reader_limits)
  if not terminal then
    return fail(self, checkpoint_error)
  end
  self.current_frame = selected.frame_index
  self.elapsed_terminal_us = selected.elapsed_terminal_us
  self.ended = false
  self.failure = nil
  self.next_frame = nil
  self.playhead_us = target
  self.state = "paused"
  return {
    checkpoint_terminal_us = selected.elapsed_terminal_us,
    frame_index = selected.frame_index,
    target_terminal_us = target,
    terminal = terminal,
  }
end

function replay_mt:seek_mark(name, occurrence)
  if type(name) ~= "string" or name == "" then
    return config_error("replay mark name must be a non-empty string", { provided = name })
  end
  local selected_occurrence = occurrence or 1
  if
    type(selected_occurrence) ~= "number"
    or selected_occurrence % 1 ~= 0
    or selected_occurrence < 1
  then
    return config_error("replay mark occurrence must be a positive integer", {
      provided = occurrence,
    })
  end
  local marks, marks_error = self:marks()
  if not marks then
    return nil, marks_error
  end
  local count = 0
  for _, mark in ipairs(marks) do
    if mark.name == name then
      count = count + 1
      if count == selected_occurrence then
        local plan, seek_error = self:seek(mark.terminal_us)
        if not plan then
          return nil, seek_error
        end
        plan.mark = mark
        return plan
      end
    end
  end
  return unavailable(
    "replay mark was not indexed",
    { name = name, occurrence = selected_occurrence }
  )
end

function replay_mt:poll(advance_us)
  local valid, valid_error = state_error(self)
  if not valid then
    return nil, valid_error
  end
  local advance, advance_error = uint32(advance_us or 0, "replay advance_us")
  if not advance then
    return nil, advance_error
  end
  if self.state == "paused" or self.state == "exhausted" then
    return {}
  end
  self.playhead_us = self.playhead_us + advance * self.speed
  local events = {}
  local processed_frames = 0
  while processed_frames < self.config.max_events_per_poll do
    local step, step_error = consume_frame(self, false)
    if step == false then
      break
    end
    if not step then
      if step_error then
        return nil, step_error
      end
      break
    end
    processed_frames = processed_frames + 1
    if step.event then
      events[#events + 1] = step.event
    end
  end
  return events
end

function replay_mt:send_input()
  return unavailable("replay backend does not accept input")
end

function replay_mt:resize()
  return unavailable("replay backend does not accept resize requests")
end

function replay_mt:stop(reason)
  if self.state == "stopped" then
    return true
  end
  self.stop_reason = reason or "stopped"
  self.state = "stopped"
  local closed, close_error = self.reader:close()
  if not closed then
    return nil, close_error
  end
  return true
end

function replay_mt:capabilities()
  return {
    deterministic_time = true,
    input = false,
    pause = true,
    resume = true,
    resize = false,
    seek = self.index_state == "ready" and #self.checkpoint_index > 0,
    speed = true,
  }
end

function replay_mt:status()
  return {
    checkpoint_status = {
      indexed = #self.checkpoint_index,
      state = self.index_state,
      total = self.checkpoint_count,
    },
    current_frame = self.current_frame,
    elapsed_terminal_us = self.elapsed_terminal_us,
    next_frame_pending = self.next_frame ~= nil,
    mark_status = {
      indexed = #self.mark_index,
      state = self.index_state,
      total = self.mark_count,
    },
    playhead_us = self.playhead_us,
    speed = self.speed,
    state = self.state,
    total_duration_us = self.total_duration_us,
  }
end

return Replay
