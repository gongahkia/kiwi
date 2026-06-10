local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\]") or ""
local root = scriptDir:gsub("[/\\]?tools[/\\]?$", "")
if root == "" then
  root = "."
end

package.path = root .. "/?.lua;" .. root .. "/tools/?.lua;" .. package.path

local Support = require("cli_support")
Support.installLoveShim()

local Actor = require("actor")
local Level = require("level")

local count = tonumber(arg[1]) or 100
local startSeed = tonumber(arg[2]) or 1
local mode = (arg[3] or "all"):lower()
local samples = tonumber(arg[4]) or 64

local enabled = {
  graph = mode == "graph" or mode == "all",
  gameplay = mode == "gameplay" or mode == "all",
  path = mode == "path" or mode == "all",
  collision = mode == "collision" or mode == "all",
  metrics = mode == "metrics" or mode == "all",
}

if not (enabled.graph or enabled.gameplay or enabled.path or enabled.collision or enabled.metrics) then
  io.write("usage: lua tools/validate_levels.lua [count] [startSeed] [graph|gameplay|path|collision|metrics|all] [pathSamples]\n")
  os.exit(2)
end

local metrics = {
  rooms = {},
  objectives = {},
  gates = {},
  refills = {},
  stairs = {},
  ladders = {},
  floorHeights = {},
  heightTransitions = {},
  steepTransitions = {},
  ceilingTransitions = {},
  reachable = {},
  objectiveDistance = {},
  returnDistance = {},
  pathLength = {},
  pathTimeMs = {},
}

local failed = 0

local function recordFailure(seed, kind, failures)
  failed = failed + 1
  io.write(string.format("fail seed=%d check=%s failures=%s\n", seed, kind, table.concat(failures, ",")))
end

local function checkGraph(seed, level)
  local validation = Level.validate(level)

  if not validation.valid then
    recordFailure(seed, "graph", validation.failures)
  end
end

local function checkGameplay(seed, level)
  local failures = {}
  local currentX = level.start.x
  local currentY = level.start.y

  for _, objective in ipairs(level.objectives) do
    Support.pathOrFail(
      Level,
      level,
      currentX,
      currentY,
      objective.x,
      objective.y,
      "objective-" .. objective.id,
      failures
    )
    objective.cell.objective.collected = true
    currentX = objective.x
    currentY = objective.y
  end

  Level.setGatesLocked(level, false)
  Support.pathOrFail(Level, level, currentX, currentY, level.start.x, level.start.y, "atrium-return", failures)

  if #failures > 0 then
    recordFailure(seed, "gameplay", failures)
  end
end

local function sampleIndex(seed, i, count)
  return ((seed * 1103515245 + i * 12345) % count) + 1
end

local function checkPathStress(seed, level)
  local cells = Support.collectReachableCells(Level, level, true)
  local failures = {}

  if #cells < 2 then
    recordFailure(seed, "path", { "not-enough-cells" })
    return
  end

  for i = 1, samples do
    local source = cells[sampleIndex(seed, i, #cells)]
    local target = cells[sampleIndex(seed + 17, i * 3, #cells)]

    if source.x ~= target.x or source.y ~= target.y then
      local started = os.clock()
      local path = Level.findPath(level, source.x, source.y, target.x, target.y)
      local elapsedMs = (os.clock() - started) * 1000

      metrics.pathTimeMs[#metrics.pathTimeMs + 1] = elapsedMs
      metrics.pathLength[#metrics.pathLength + 1] = #path

      if #path == 0 then
        failures[#failures + 1] = string.format("path-%d-%d:%d-%d:%d", source.x, source.y, target.x, target.y, i)
      end
    end
  end

  if #failures > 0 then
    recordFailure(seed, "path", failures)
  end
end

local function checkCollision(seed, level)
  local failures = {}
  local player = Actor.createPlayer(level)
  local enemy = Actor.createEnemy(level)

  if not Actor.canOccupy(level, player) then
    failures[#failures + 1] = "player-spawn"
  end

  if not Actor.canOccupy(level, enemy) then
    failures[#failures + 1] = "enemy-spawn"
  end

  if #failures > 0 then
    recordFailure(seed, "collision", failures)
  end
end

local function appendCoreMetrics(level)
  local validation = Level.validate(level)

  metrics.rooms[#metrics.rooms + 1] = #level.rooms
  metrics.objectives[#metrics.objectives + 1] = #level.objectives
  metrics.gates[#metrics.gates + 1] = #level.gates
  metrics.refills[#metrics.refills + 1] = #level.refills
  metrics.stairs[#metrics.stairs + 1] = level.stairCount
  metrics.ladders[#metrics.ladders + 1] = level.ladderCount
  metrics.floorHeights[#metrics.floorHeights + 1] = validation.floorHeights
  metrics.heightTransitions[#metrics.heightTransitions + 1] = validation.heightTransitions
  metrics.steepTransitions[#metrics.steepTransitions + 1] = validation.steepTransitions
  metrics.ceilingTransitions[#metrics.ceilingTransitions + 1] = validation.ceilingTransitions
  metrics.reachable[#metrics.reachable + 1] = validation.reachable
end

local function appendRouteMetrics(level)
  local currentX = level.start.x
  local currentY = level.start.y

  for _, objective in ipairs(level.objectives) do
    local distance = Support.pathOrFail(Level, level, currentX, currentY, objective.x, objective.y, "metric-objective", {})
    if distance then
      metrics.objectiveDistance[#metrics.objectiveDistance + 1] = distance
    end
    currentX = objective.x
    currentY = objective.y
  end

  Support.withGates(level, false, function()
    local distance = Support.pathOrFail(Level, level, currentX, currentY, level.start.x, level.start.y, "metric-return", {})
    if distance then
      metrics.returnDistance[#metrics.returnDistance + 1] = distance
    end
  end)
end

local function collectMetrics(level)
  appendCoreMetrics(level)
  appendRouteMetrics(level)
end

for i = 0, count - 1 do
  local seed = startSeed + i
  love.math.setRandomSeed(seed)

  local level = Level.generate(Level.width, Level.height)

  if enabled.graph then
    checkGraph(seed, level)
  end
  if enabled.path then
    checkPathStress(seed, level)
  end
  if enabled.collision then
    checkCollision(seed, level)
  end
  if enabled.metrics then
    collectMetrics(level)
  end
  if enabled.gameplay then
    checkGameplay(seed, level)
  end
end

if enabled.metrics then
  io.write(Support.metricLine("rooms", metrics.rooms) .. "\n")
  io.write(Support.metricLine("objectives", metrics.objectives) .. "\n")
  io.write(Support.metricLine("gates", metrics.gates) .. "\n")
  io.write(Support.metricLine("refills", metrics.refills) .. "\n")
  io.write(Support.metricLine("stairs", metrics.stairs) .. "\n")
  io.write(Support.metricLine("ladders", metrics.ladders) .. "\n")
  io.write(Support.metricLine("floor-heights", metrics.floorHeights) .. "\n")
  io.write(Support.metricLine("height-transitions", metrics.heightTransitions) .. "\n")
  io.write(Support.metricLine("steep-transitions", metrics.steepTransitions) .. "\n")
  io.write(Support.metricLine("ceiling-transitions", metrics.ceilingTransitions) .. "\n")
  io.write(Support.metricLine("reachable", metrics.reachable) .. "\n")
  io.write(Support.percentileLine("objective-distance", metrics.objectiveDistance) .. "\n")
  io.write(Support.percentileLine("return-distance", metrics.returnDistance) .. "\n")
  if enabled.path then
    io.write(Support.percentileLine("path-length", metrics.pathLength) .. "\n")
    io.write(Support.percentileLine("path-time-ms", metrics.pathTimeMs) .. "\n")
  end
end

if failed > 0 then
  io.write(string.format("failed %d checks across %d seeds from %d mode=%s\n", failed, count, startSeed, mode))
  os.exit(1)
end

io.write(string.format("ok %d seeds from %d mode=%s\n", count, startSeed, mode))
