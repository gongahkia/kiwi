local Errors = require("runtime.errors")
local Frames = require("recording.frames")
local RecordingReader = require("recording.reader")

local Replay = {}
local replay_mt = {}
replay_mt.__index = replay_mt

Replay.contract = {
  constructor = "new(source, config?) -> replay_backend | nil, error",
  pause = "pause() -> true | nil, error",
  play = "play() -> true | nil, error",
  resume = "resume() -> true | nil, error",
  set_speed = "set_speed(multiplier) -> true | nil, error",
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
  return {
    max_events_per_poll = max_events,
    reader_limits = reader_limits,
    speed = speed,
  }
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

local function fail(replay, error_value)
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
    elapsed_terminal_us = 0,
    ended = false,
    failure = nil,
    next_frame = nil,
    playhead_us = 0,
    reader = reader,
    speed = settings.speed,
    state = "idle",
    stop_reason = nil,
  }, replay_mt)
end

function replay_mt:start()
  if self.state == "stopped" then
    return exited("stopped replay backends cannot restart")
  end
  if self.state == "failed" then
    return nil, self.failure
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
    local loaded, load_error = load_next(self)
    if not loaded then
      return nil, load_error
    end
    if self.ended then
      break
    end
    local due_us = self.elapsed_terminal_us + self.next_frame.delta_us
    if self.playhead_us < due_us then
      break
    end
    local frame = self.next_frame
    self.next_frame = nil
    self.current_frame = self.current_frame + 1
    self.elapsed_terminal_us = due_us
    processed_frames = processed_frames + 1
    local event, event_error = replayable_event(frame)
    if event_error then
      return fail(self, event_error)
    end
    if event then
      events[#events + 1] = event
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
    speed = true,
  }
end

function replay_mt:status()
  return {
    current_frame = self.current_frame,
    elapsed_terminal_us = self.elapsed_terminal_us,
    next_frame_pending = self.next_frame ~= nil,
    playhead_us = self.playhead_us,
    speed = self.speed,
    state = self.state,
  }
end

return Replay
