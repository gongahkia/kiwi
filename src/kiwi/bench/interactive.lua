-- Controlled acknowledgment timing. Unrelated output/presents never complete
-- an input sample; one outstanding sequence bounds both work and storage.
local Stats = require("kiwi.bench.stats")
local Interactive = {}
Interactive.__index = Interactive
Interactive.maximum_response_seconds = 2

local function integer(value, minimum, maximum)
  return type(value) == "number" and value % 1 == 0 and value >= minimum and value <= maximum
end

local function time(value)
  assert(type(value) == "number" and value >= 0 and value < math.huge, "invalid monotonic timestamp")
  return value
end

function Interactive.visible_sequence(state)
  local sequence = state.title == "kiwi-bench-ready" and 0
    or tonumber((state.title or ""):match("^kiwi%-bench%-ack:(%d+)$"))
  if not integer(sequence, 0, 288) then return nil end
  local expected = sequence == 0 and "READY0000" or string.format("ACK%04d", sequence)
  if state.columns < #expected then return nil end
  for column = 0, #expected - 1 do
    if state:get(column, 0).glyph ~= expected:sub(column + 1, column + 1) then return nil end
  end
  return sequence
end

function Interactive.new(options)
  assert(integer(options.samples, 1, 256) and integer(options.warmup, 0, 32), "interactive sample counts out of bounds")
  return setmetatable({ launched_at = time(options.launched_at), samples = options.samples, warmup = options.warmup,
    sent = 0, completed = 0, callback_to_parse_ms = {}, parse_to_present_return_ms = {},
    callback_to_present_return_ms = {} }, Interactive)
end

function Interactive:input(now)
  assert(self.ready_at and not self.pending and not self:done(), "input requires ready, idle measurement")
  assert(time(now) >= self.ready_at and (not self.last_present or now >= self.last_present), "input clock moved backwards")
  self.sent = self.sent + 1
  self.pending = { sequence = self.sent, input_at = now }
  return self.sent
end

function Interactive:parsed(sequence, now)
  assert(integer(sequence, 1, self.sent), "unexpected acknowledgment sequence")
  local pending = self.pending
  if not pending or sequence < pending.sequence then return false end
  assert(time(now) >= pending.input_at, "parse precedes input")
  if pending.parsed_at then return false end
  pending.parsed_at = now
  return true
end

function Interactive:present(now, sequence)
  assert(time(now) >= self.launched_at and (not self.last_present or now >= self.last_present), "presentation clock moved backwards")
  self.first_present_at = self.first_present_at or now
  self.last_present = now
  if sequence == 0 then self.ready_at = self.ready_at or now; return false end
  if sequence == nil then return false end
  assert(integer(sequence, 1, self.sent), "unexpected presented acknowledgment")
  local pending = self.pending
  if not pending or sequence < pending.sequence then return false end
  assert(pending.parsed_at and now >= pending.parsed_at, "presented acknowledgment was not parsed")
  assert(now - pending.input_at < Interactive.maximum_response_seconds, "acknowledgment exceeded the responsiveness ceiling")
  self.completed = self.completed + 1
  if self.completed > self.warmup then
    local index = self.completed - self.warmup
    self.callback_to_parse_ms[index] = (pending.parsed_at - pending.input_at) * 1000
    self.parse_to_present_return_ms[index] = (now - pending.parsed_at) * 1000
    self.callback_to_present_return_ms[index] = (now - pending.input_at) * 1000
  end
  self.pending = nil
  return true
end

function Interactive:done() return self.completed == self.warmup + self.samples end

function Interactive:observations()
  local result = { samples = #self.callback_to_present_return_ms, requested_samples = self.samples,
    warmup = self.warmup, completed = self.completed, sent = self.sent,
    launch_to_first_present_return_ms = self.first_present_at and (self.first_present_at - self.launched_at) * 1000,
    launch_to_child_ready_present_return_ms = self.ready_at and (self.ready_at - self.launched_at) * 1000 }
  for _, name in ipairs({ "callback_to_parse_ms", "parse_to_present_return_ms", "callback_to_present_return_ms" }) do
    local values = self[name]
    local value = #values > 0 and Stats.summary(values) or { count = 0 }
    if #values > 0 then value.maximum, value.minimum = math.max(unpack(values)), math.min(unpack(values)) end
    value.values = values
    result[name] = value
  end
  return result
end

function Interactive:snapshot()
  assert(self:done() and self.ready_at, "interactive measurement is incomplete")
  return self:observations()
end

return Interactive
