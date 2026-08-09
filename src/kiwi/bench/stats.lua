local Stats = {}

local function sorted_copy(values)
  local copy = {}
  for index, value in ipairs(values) do
    copy[index] = value
  end
  table.sort(copy)
  return copy
end

function Stats.percentile(values, percentile)
  assert(#values > 0, "cannot calculate a percentile for no samples")
  assert(percentile >= 0 and percentile <= 1, "percentile must be within [0, 1]")
  local sorted = sorted_copy(values)
  local position = (percentile * (#sorted - 1)) + 1
  local lower = math.floor(position)
  local upper = math.ceil(position)
  if lower == upper then
    return sorted[lower]
  end
  local amount = position - lower
  return sorted[lower] + (sorted[upper] - sorted[lower]) * amount
end

function Stats.summary(values)
  assert(#values > 0, "cannot summarise no samples")
  local total = 0
  for _, value in ipairs(values) do
    total = total + value
  end
  return {
    count = #values,
    total = total,
    mean = total / #values,
    p50 = Stats.percentile(values, 0.50),
    p95 = Stats.percentile(values, 0.95),
    p99 = Stats.percentile(values, 0.99),
  }
end

return Stats
