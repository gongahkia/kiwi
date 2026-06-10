local Support = {}
local unpack = table.unpack or unpack

local function scriptRoot(scriptPath)
  local scriptDir = (scriptPath or ""):match("^(.*)[/\\]") or ""
  local root = scriptDir:gsub("[/\\]?tools[/\\]?$", "")

  if root == "" then
    root = "."
  end

  return root
end

function Support.configurePackagePath(scriptPath)
  local root = scriptRoot(scriptPath)
  package.path = root .. "/?.lua;" .. root .. "/tools/?.lua;" .. package.path
  return root
end

function Support.installLoveShim()
  local state = 1

  local function setRandomSeed(seed)
    state = math.floor(tonumber(seed) or 1) % 2147483647
    if state <= 0 then
      state = state + 2147483646
    end
  end

  local function nextRandom()
    state = (state * 48271) % 2147483647
    return state / 2147483647
  end

  love = love or {}
  love.math = love.math or {}
  love.math.setRandomSeed = love.math.setRandomSeed or setRandomSeed
  love.math.random = love.math.random or function(low, high)
    local value = nextRandom()

    if low == nil then
      return value
    end

    if high == nil then
      return math.floor(value * low) + 1
    end

    return math.floor(value * (high - low + 1)) + low
  end
end

function Support.withGates(level, locked, callback)
  local states = {}

  for i, gate in ipairs(level.gates or {}) do
    states[i] = gate.cell.gateLocked
    gate.cell.gateLocked = locked
  end

  local results = { pcall(callback) }

  for i, gate in ipairs(level.gates or {}) do
    gate.cell.gateLocked = states[i]
  end

  if not results[1] then
    error(results[2])
  end

  table.remove(results, 1)
  return unpack(results)
end

function Support.collectReachableCells(Level, level, gatesLocked)
  return Support.withGates(level, gatesLocked, function()
    local _, visited = Level.farthestCellFrom(level, level.start.x, level.start.y)
    local cells = {}

    for y = 1, level.height do
      for x = 1, level.width do
        if visited[x .. ":" .. y] then
          cells[#cells + 1] = { x = x, y = y }
        end
      end
    end

    return cells, visited
  end)
end

function Support.pathOrFail(Level, level, fromX, fromY, toX, toY, label, failures)
  if fromX == toX and fromY == toY then
    return 0
  end

  local path = Level.findPath(level, fromX, fromY, toX, toY)
  if #path == 0 then
    failures[#failures + 1] = label
    return nil
  end

  return #path
end

function Support.pushAll(target, source)
  for _, value in ipairs(source) do
    target[#target + 1] = value
  end
end

function Support.sum(values)
  local total = 0

  for _, value in ipairs(values) do
    total = total + value
  end

  return total
end

function Support.stats(values)
  if #values == 0 then
    return { min = 0, avg = 0, max = 0 }
  end

  local minValue = values[1]
  local maxValue = values[1]
  local total = 0

  for _, value in ipairs(values) do
    if value < minValue then
      minValue = value
    end
    if value > maxValue then
      maxValue = value
    end
    total = total + value
  end

  return { min = minValue, avg = total / #values, max = maxValue }
end

function Support.percentile(values, percentile)
  if #values == 0 then
    return 0
  end

  local sorted = {}
  for i, value in ipairs(values) do
    sorted[i] = value
  end

  table.sort(sorted)

  local index = math.ceil(#sorted * percentile)
  if index < 1 then
    index = 1
  elseif index > #sorted then
    index = #sorted
  end

  return sorted[index]
end

function Support.metricLine(label, values)
  local stat = Support.stats(values)
  return string.format("%s min=%.1f avg=%.1f max=%.1f", label, stat.min, stat.avg, stat.max)
end

function Support.percentileLine(label, values)
  return string.format(
    "%s p50=%.1f p90=%.1f p99=%.1f max=%.1f",
    label,
    Support.percentile(values, 0.50),
    Support.percentile(values, 0.90),
    Support.percentile(values, 0.99),
    Support.percentile(values, 1.00)
  )
end

return Support
