local Invalidation = {}
Invalidation.__index = Invalidation

Invalidation.reasons = {
  terminal = true,
  resize = true,
  cursor = true,
  selection = true,
  configuration = true,
  extension = true,
}

function Invalidation.new(options)
  options = options or {}
  local minimum_interval = options.minimum_interval or 1 / 60
  local maximum_delay = options.maximum_delay or 60
  assert(type(minimum_interval) == "number" and minimum_interval > 0, "invalidation minimum interval must be positive")
  assert(type(maximum_delay) == "number" and maximum_delay >= minimum_interval, "invalidation maximum delay must exceed minimum interval")
  return setmetatable({
    reasons = {},
    deadline = nil,
    minimum_interval = minimum_interval,
    maximum_delay = maximum_delay,
  }, Invalidation)
end

function Invalidation:request(reason)
  assert(Invalidation.reasons[reason], "unknown invalidation reason " .. tostring(reason))
  self.reasons[reason] = true
end

function Invalidation:schedule(reason, now, delay)
  assert(Invalidation.reasons[reason], "unknown invalidation reason " .. tostring(reason))
  assert(type(now) == "number" and type(delay) == "number", "invalidation deadlines need numeric time and delay")
  local clamped = math.max(self.minimum_interval, math.min(self.maximum_delay, delay))
  local deadline = now + clamped
  if self.deadline == nil or deadline < self.deadline then self.deadline = deadline end
  return self.deadline
end

function Invalidation:due(now)
  return next(self.reasons) ~= nil or self.deadline ~= nil and now >= self.deadline
end

function Invalidation:next_deadline()
  return self.deadline
end

function Invalidation:consume_success(now)
  self.reasons = {}
  if self.deadline ~= nil and now >= self.deadline then self.deadline = nil end
end

function Invalidation:snapshot()
  local reasons = {}
  for reason in pairs(self.reasons) do reasons[#reasons + 1] = reason end
  table.sort(reasons)
  return { reasons = reasons, deadline = self.deadline, minimum_interval = self.minimum_interval, maximum_delay = self.maximum_delay }
end

return Invalidation
