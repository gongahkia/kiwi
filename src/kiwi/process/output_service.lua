-- Cooperative ordinary PTY output service. The byte ceiling bounds work even
-- with a coarse clock; the elapsed budget lets cold/expensive parsing yield.
-- A chunk cannot be preempted. Input must be flushed before calling drain.
local Service = {}
Service.__index = Service
Service.default_max_bytes = 16 * 1024
Service.chunk_bytes = 4 * 1024
Service.max_seconds = 0.008

function Service.new(options)
  options = options or {}
  local bytes = options.max_bytes or Service.default_max_bytes
  assert(type(bytes) == "number" and bytes >= 1 and bytes < math.huge and bytes % 1 == 0,
    "output service requires a positive integer byte budget")
  assert(type(options.clock) == "function", "output service requires a monotonic wall clock")
  return setmetatable({ max_bytes = bytes, clock = options.clock, pending = false }, Service)
end

function Service:drain(sessions, consume)
  local count = #sessions
  self.pending = false
  if count == 0 then self.next_pty = nil; return 0, 0 end
  local index = 1
  for candidate, session in ipairs(sessions) do
    if session.pty == self.next_pty then index = candidate; break end
  end
  local quantum = math.min(Service.chunk_bytes, math.max(1, math.floor(self.max_bytes / count)))
  local remaining, calls, drained, empty = self.max_bytes, 0, 0, {}
  local started = self.clock()
  local previous = started
  while remaining > 0 and drained < count do
    if not empty[index] then
      local session = sessions[index]
      local requested = math.min(quantum, remaining)
      local output = session.pty:read_available(requested)
      assert(type(output) == "string" and #output <= requested, "PTY exceeded its output service allowance")
      calls, remaining = calls + 1, remaining - #output
      if #output < requested or session.pty.eof then
        empty[index], drained = true, drained + 1
      end
      index = index % count + 1
      -- Retain identity, not an array position: panes can move or close between
      -- turns. Advance before parsing so the next hot pane gets the next turn.
      self.next_pty = sessions[index].pty
      if #output > 0 then consume(session, output) end
      local now = self.clock()
      assert(now >= previous, "output service clock moved backwards")
      previous = now
      if now - started >= Service.max_seconds then break end
    else
      index = index % count + 1
    end
  end
  -- Arrange an immediate host turn when work was deferred, even if a skipped
  -- session's previous read happened to empty its descriptor.
  self.pending = drained < count
  return self.max_bytes - remaining, calls
end

return Service
