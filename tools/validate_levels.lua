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
  gates = {},
  keys = {},
  exitKeys = {},
  locks = {},
  hazards = {},
  districts = {},
  districtKinds = {},
  nests = {},
  signals = {},
  factions = {},
  cycleShelters = {},
  roomModifiers = {},
  creatureSpawns = {},
  npcSpawns = {},
  refills = {},
  stairs = {},
  ladders = {},
  floorHeights = {},
  heightTransitions = {},
  steepTransitions = {},
  ceilingTransitions = {},
  reachable = {},
  keyDistance = {},
  exitDistance = {},
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

  for _, key in ipairs(level.keys or {}) do
    Support.pathOrFail(
      Level,
      level,
      currentX,
      currentY,
      key.x,
      key.y,
      "key-" .. key.id,
      failures
    )
    key.cell.key.collected = true
    Level.setLocksLocked(level, false)
    currentX = key.x
    currentY = key.y
  end

  Level.setGatesLocked(level, false)

  if level.exit then
    Support.pathOrFail(Level, level, currentX, currentY, level.exit.x, level.exit.y, "exit", failures)
  else
    failures[#failures + 1] = "exit-missing"
  end

  if #failures > 0 then
    recordFailure(seed, "gameplay-deck" .. (level.deck or 1), failures)
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
  local creatures = Actor.createCreatures(level)

  if not Actor.canOccupy(level, player) then
    failures[#failures + 1] = "player-spawn"
  end

  if not Actor.canOccupy(level, enemy) then
    failures[#failures + 1] = "enemy-spawn"
  end

  for _, creature in ipairs(creatures) do
    if not Actor.canOccupy(level, creature) then
      failures[#failures + 1] = "creature-spawn-" .. creature.kind .. "-" .. creature.id
    end
  end

  if #failures > 0 then
    recordFailure(seed, "collision", failures)
  end
end

local function appendCoreMetrics(level)
  local validation = Level.validate(level)

  metrics.rooms[#metrics.rooms + 1] = #level.rooms
  metrics.gates[#metrics.gates + 1] = #level.gates
  metrics.keys[#metrics.keys + 1] = #(level.keys or {})
  metrics.exitKeys[#metrics.exitKeys + 1] = level.exitKey and 1 or 0
  metrics.locks[#metrics.locks + 1] = #(level.locks or {})
  metrics.hazards[#metrics.hazards + 1] = #(level.hazards or {})
  metrics.districts[#metrics.districts + 1] = validation.districts or 0
  metrics.districtKinds[#metrics.districtKinds + 1] = validation.districtKinds or 0
  metrics.nests[#metrics.nests + 1] = validation.nests or 0
  metrics.signals[#metrics.signals + 1] = validation.signals or 0
  metrics.factions[#metrics.factions + 1] = validation.factions or 0
  metrics.cycleShelters[#metrics.cycleShelters + 1] = validation.cycleShelters or 0
  metrics.roomModifiers[#metrics.roomModifiers + 1] = validation.roomModifiers or 0
  metrics.creatureSpawns[#metrics.creatureSpawns + 1] = validation.creatureSpawns or 0
  metrics.npcSpawns[#metrics.npcSpawns + 1] = validation.npcSpawns or 0
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

  for _, key in ipairs(level.keys or {}) do
    local distance = Support.pathOrFail(Level, level, currentX, currentY, key.x, key.y, "metric-key", {})
    if distance then
      metrics.keyDistance[#metrics.keyDistance + 1] = distance
      currentX = key.x
      currentY = key.y
      Level.setLocksLocked(level, false)
    end
  end

  Support.withGates(level, false, function()
    if level.exit then
      local distance = Support.pathOrFail(Level, level, currentX, currentY, level.exit.x, level.exit.y, "metric-exit", {})
      if distance then
        metrics.exitDistance[#metrics.exitDistance + 1] = distance
      end
    end
  end)
  Level.setLocksLocked(level, true)
end

local function collectMetrics(level)
  appendCoreMetrics(level)
  appendRouteMetrics(level)
end

local function validationBranch(seed, deck)
  local order = Level.biomeOrder or {}
  local biome = order[((seed + deck - 2) % #order) + 1]
  local profile = Level.biomeProfiles[biome]
  return {
    kind = (seed + deck) % 3 == 0 and "conflict" or ((seed + deck) % 2 == 0 and "salvage" or "safe"),
    biome = biome,
    risk = ((seed + deck) % 3) + 1,
    salvage = ((seed + deck + 1) % 3) + 1,
    faction = profile and profile.primaryFaction or "scavenger",
    incident = profile and profile.incidents[((seed + deck - 1) % #profile.incidents) + 1] or nil,
  }
end

for i = 0, count - 1 do
  local seed = startSeed + i
  for deck = 1, Level.maxDecks do
    love.math.setRandomSeed(seed + deck * 1000003)

    local level = Level.generate(nil, nil, deck, validationBranch(seed, deck))
    local labelSeed = seed * 10 + deck

    if enabled.graph then
      checkGraph(labelSeed, level)
    end
    if enabled.path then
      checkPathStress(labelSeed, level)
    end
    if enabled.collision then
      checkCollision(labelSeed, level)
    end
    if enabled.metrics then
      collectMetrics(level)
    end
    if enabled.gameplay then
      checkGameplay(labelSeed, level)
    end
  end
end

if enabled.metrics then
  io.write(Support.metricLine("rooms", metrics.rooms) .. "\n")
  io.write(Support.metricLine("gates", metrics.gates) .. "\n")
  io.write(Support.metricLine("keys", metrics.keys) .. "\n")
  io.write(Support.metricLine("exit-keys", metrics.exitKeys) .. "\n")
  io.write(Support.metricLine("locks", metrics.locks) .. "\n")
  io.write(Support.metricLine("hazards", metrics.hazards) .. "\n")
  io.write(Support.metricLine("districts", metrics.districts) .. "\n")
  io.write(Support.metricLine("district-kinds", metrics.districtKinds) .. "\n")
  io.write(Support.metricLine("nests", metrics.nests) .. "\n")
  io.write(Support.metricLine("signals", metrics.signals) .. "\n")
  io.write(Support.metricLine("factions", metrics.factions) .. "\n")
  io.write(Support.metricLine("cycle-shelters", metrics.cycleShelters) .. "\n")
  io.write(Support.metricLine("room-modifiers", metrics.roomModifiers) .. "\n")
  io.write(Support.metricLine("creature-spawns", metrics.creatureSpawns) .. "\n")
  io.write(Support.metricLine("npc-spawns", metrics.npcSpawns) .. "\n")
  io.write(Support.metricLine("refills", metrics.refills) .. "\n")
  io.write(Support.metricLine("stairs", metrics.stairs) .. "\n")
  io.write(Support.metricLine("ladders", metrics.ladders) .. "\n")
  io.write(Support.metricLine("floor-heights", metrics.floorHeights) .. "\n")
  io.write(Support.metricLine("height-transitions", metrics.heightTransitions) .. "\n")
  io.write(Support.metricLine("steep-transitions", metrics.steepTransitions) .. "\n")
  io.write(Support.metricLine("ceiling-transitions", metrics.ceilingTransitions) .. "\n")
  io.write(Support.metricLine("reachable", metrics.reachable) .. "\n")
  io.write(Support.percentileLine("key-distance", metrics.keyDistance) .. "\n")
  io.write(Support.percentileLine("exit-distance", metrics.exitDistance) .. "\n")
  if enabled.path then
    io.write(Support.percentileLine("path-length", metrics.pathLength) .. "\n")
    io.write(Support.percentileLine("path-time-ms", metrics.pathTimeMs) .. "\n")
  end
end

if failed > 0 then
  io.write(string.format("failed %d checks across %d seeds x %d decks from %d mode=%s\n", failed, count, Level.maxDecks, startSeed, mode))
  os.exit(1)
end

io.write(string.format("ok %d seeds x %d decks from %d mode=%s\n", count, Level.maxDecks, startSeed, mode))
