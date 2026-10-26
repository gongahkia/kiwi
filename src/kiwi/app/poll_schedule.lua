local Schedule = {}

-- A full read budget suggests unread output. Yield to the host between bounded
-- reads without sleeping; an expired render deadline is also runnable now.
function Schedule.timeout(now, deadline, budget_exhausted)
  if budget_exhausted then return 0 end
  if deadline ~= nil then return math.max(0, deadline - now) end
  return math.huge
end

-- Older kernels/resource exhaustion may prevent an exit watch. Only those
-- children require periodic waitpid; EOF alone does not imply process exit.
function Schedule.child_timeout(ptys, minimized)
  for _, pty in ipairs(ptys) do
    if pty.pid ~= nil and not pty.exited and pty.exit_fd == nil then
      return minimized and 0.250 or 0.050
    end
  end
  return math.huge
end

return Schedule
