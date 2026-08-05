local Errors = require("runtime.errors")

local Subscriptions = {}
local subscriptions_mt = {}
subscriptions_mt.__index = subscriptions_mt

Subscriptions.contract = {
  apply = "apply(event, semantic_events, terminal, timestamp_us) -> true | nil, error",
  constructor = "new(effect_host, terminal) -> subscriptions | nil, error",
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

local function valid_effect_host(value)
  if type(value) ~= "table" then
    return config_error("coordinator effect host must be a table")
  end
  for _, name in ipairs({ "advance", "emit", "limits", "resize" }) do
    if type(value[name]) ~= "function" then
      return config_error("coordinator effect host is incomplete", { method = name })
    end
  end
  local limits, limits_error = value:limits()
  if not limits then
    return nil, limits_error
  end
  if type(limits) ~= "table" then
    return config_error("coordinator effect host limits are invalid")
  end
  local payload_limit, payload_error =
    positive_integer(limits.max_event_payload_bytes, "coordinator effect payload limit")
  if not payload_limit then
    return nil, payload_error
  end
  local range_limit, range_error =
    positive_integer(limits.max_callbacks_per_frame, "coordinator effect damage range limit")
  if not range_limit then
    return nil, range_error
  end
  return value, payload_limit, range_limit
end

local function take_damage(terminal)
  if type(terminal) ~= "table" or type(terminal.take_damage) ~= "function" then
    return config_error("coordinator terminal must expose take_damage for effects")
  end
  local ranges = terminal:take_damage()
  if type(ranges) ~= "table" then
    return config_error("terminal damage handoff is invalid")
  end
  return ranges
end

local function emit(host, kind, payload, timestamp_us)
  local emitted, emit_error = host:emit(kind, payload, timestamp_us)
  if not emitted then
    return nil, emit_error
  end
  return true
end

local function emit_bytes(subscriptions, kind, bytes, timestamp_us)
  if #bytes == 0 then
    return emit(subscriptions.host, kind, { bytes = bytes }, timestamp_us)
  end
  local offset = 1
  while offset <= #bytes do
    local finish = math.min(#bytes, offset + subscriptions.max_event_payload_bytes - 1)
    local emitted, emit_error =
      emit(subscriptions.host, kind, { bytes = bytes:sub(offset, finish) }, timestamp_us)
    if not emitted then
      return nil, emit_error
    end
    offset = finish + 1
  end
  return true
end

local function emit_semantic_event(subscriptions, event, timestamp_us)
  if event.kind == "bell" then
    return emit(subscriptions.host, "bell", {}, timestamp_us)
  end
  if event.kind == "cursor_moved" then
    return emit(subscriptions.host, "cursor", {
      column = event.column,
      row = event.row,
    }, timestamp_us)
  end
  if event.kind == "scrolled" then
    return emit(subscriptions.host, "scroll", {
      bottom = event.bottom,
      count = event.count,
      direction = event.direction,
      top = event.top,
    }, timestamp_us)
  end
  if event.kind == "buffer_changed" then
    return emit(subscriptions.host, "screen_switch", { screen = event.active_buffer }, timestamp_us)
  end
  return true
end

function Subscriptions.new(effect_host, terminal)
  local host, payload_limit_or_error, range_limit_or_error = valid_effect_host(effect_host)
  if not host then
    return nil, payload_limit_or_error
  end
  local _, damage_error = take_damage(terminal)
  if damage_error then
    return nil, damage_error
  end
  return setmetatable({
    host = host,
    max_damage_ranges = range_limit_or_error,
    max_event_payload_bytes = payload_limit_or_error,
  }, subscriptions_mt)
end

function subscriptions_mt:apply(event, semantic_events, terminal, timestamp_us)
  local advanced, advance_error = self.host:advance(event.delta_us)
  if not advanced then
    return nil, advance_error
  end
  if event.kind == "input" or event.kind == "output" then
    local emitted, emit_error = emit_bytes(self, event.kind, event.data, timestamp_us)
    if not emitted then
      return nil, emit_error
    end
  elseif event.kind == "resize" then
    local viewport
    if event.pixel_width > 0 and event.pixel_height > 0 then
      viewport = { height = event.pixel_height, width = event.pixel_width }
    end
    local resized, resize_error = self.host:resize(viewport, {
      columns = event.columns,
      rows = event.rows,
    }, timestamp_us)
    if not resized then
      return nil, resize_error
    end
  end
  for _, semantic_event in ipairs(semantic_events) do
    local emitted, emit_error = emit_semantic_event(self, semantic_event, timestamp_us)
    if not emitted then
      return nil, emit_error
    end
  end
  local ranges, damage_error = take_damage(terminal)
  if not ranges then
    return nil, damage_error
  end
  local offset = 1
  while offset <= #ranges do
    local finish = math.min(#ranges, offset + self.max_damage_ranges - 1)
    local chunk = {}
    for index = offset, finish do
      chunk[#chunk + 1] = ranges[index]
    end
    local emitted, emit_error = emit(self.host, "damage", { ranges = chunk }, timestamp_us)
    if not emitted then
      return nil, emit_error
    end
    offset = finish + 1
  end
  return true
end

return Subscriptions
