local Schedule = {}

-- A full read budget suggests unread output. Yield to the host between bounded
-- reads without sleeping; an expired render deadline is also runnable now.
function Schedule.timeout(now, deadline, budget_exhausted, minimized)
  if budget_exhausted then return 0 end
  local maximum = minimized and 0.250 or 0.050
  if deadline ~= nil then return math.max(0, math.min(deadline - now, maximum)) end
  return maximum
end

return Schedule
