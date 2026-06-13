local Actor = require("actor")
local Audio = require("audio")
local Cycles = require("content.cycles")
local NPCContent = require("content.npcs")
local Level = require("level")
local Renderer = require("renderer")
local UI = require("ui")
local U = require("utils")

local floor = math.floor
local abs = math.abs
local max = math.max
local min = math.min

local defaultBindings = {
  forward = "w",
  back = "s",
  strafeLeft = "a",
  strafeRight = "d",
  turnLeft = "q",
  turnRight = "e",
  sprint = "lshift",
  interact = "f",
  useTool = "space",
  cycleTool = "tab",
  map = "m",
  status = "h",
  pause = "escape",
}

local bindingActions = {
  "forward",
  "back",
  "strafeLeft",
  "strafeRight",
  "turnLeft",
  "turnRight",
  "sprint",
  "interact",
  "useTool",
  "cycleTool",
  "map",
  "status",
  "pause",
}

local Game = {
  level = nil,
  player = nil,
  enemy = nil,
  creatures = {},
  npcs = {},
  state = "playing",
  survivalTime = 0,
  bestTime = 0,
  seed = 0,
  lastSeed = 0,
  deck = 1,
  maxDecks = Level.maxDecks,
  fonts = {},
  keys = { total = 0, collected = 0, small = 0, exit = false },
  loopDuration = 60,
  loopTimer = 60,
  respawn = nil,
  mapHeld = false,
  mapGamepadHeld = false,
  statusHeld = false,
  statusGamepadHeld = false,
  torch = { fuel = 1 },
  noise = { ttl = 0, intensity = 0, radius = 0, x = 0, y = 0 },
  noises = {},
  effects = {},
  props = {},
  ecology = nil,
  signals = {},
  survey = { ttl = 0 },
  toolWheel = { visible = false, timer = 0 },
  paused = false,
  settingsIndex = 1,
  bindTarget = nil,
  bindings = {},
  achievements = { unlocked = {}, events = {} },
  demoMode = false,
  inventory = {
    selected = "flare",
    flare = 1,
    noisemaker = 1,
    scent = 1,
    snare = 0,
    pheromone = 1,
    probe = 1,
    oil = 1,
    beacon = 0,
    max = { flare = 3, noisemaker = 3, scent = 3, snare = 2, pheromone = 2, probe = 2, oil = 3, beacon = 2 },
  },
  message = "",
  messageTimer = 0,
  hazardTimer = 0,
  conversation = { active = false, npc = nil, topics = {}, index = 1, response = "" },
  seedEntry = { active = false, text = "" },
}

local function newSeed()
  return os.time() + floor(love.timer.getTime() * 1000)
end

local function setMessage(text, duration)
  Game.message = text
  Game.messageTimer = duration or 2
end

Game.setMessage = setMessage

local function copyDefaultBindings()
  local bindings = {}
  for action, key in pairs(defaultBindings) do
    bindings[action] = key
  end
  return bindings
end

local function actionKey(action)
  return Game.bindings[action] or defaultBindings[action]
end

function Game.actionDown(action)
  local key = actionKey(action)
  if not key then
    return false
  end
  return love.keyboard.isDown(key)
end

local function saveSettings()
  if not love.filesystem then
    return
  end

  local lines = {}
  for _, action in ipairs(bindingActions) do
    lines[#lines + 1] = action .. "=" .. (Game.bindings[action] or defaultBindings[action])
  end
  pcall(love.filesystem.write, "settings.txt", table.concat(lines, "\n"))
end

local function loadSettings()
  Game.bindings = copyDefaultBindings()
  if not love.filesystem or not love.filesystem.getInfo or not love.filesystem.getInfo("settings.txt") then
    return
  end

  local ok, data = pcall(love.filesystem.read, "settings.txt")
  if not ok or not data then
    return
  end

  for line in data:gmatch("[^\n]+") do
    local action, key = line:match("^([^=]+)=([^=]+)$")
    if action and key and defaultBindings[action] then
      Game.bindings[action] = key
    end
  end
end

local function saveAchievements()
  if not love.filesystem then
    return
  end

  local lines = {}
  for id, text in pairs(Game.achievements.unlocked or {}) do
    lines[#lines + 1] = id .. "|" .. text
  end
  pcall(love.filesystem.write, "achievements.txt", table.concat(lines, "\n"))
end

local function loadAchievements()
  Game.achievements = { unlocked = {}, events = {} }
  if not love.filesystem or not love.filesystem.getInfo or not love.filesystem.getInfo("achievements.txt") then
    return
  end

  local ok, data = pcall(love.filesystem.read, "achievements.txt")
  if not ok or not data then
    return
  end

  for line in data:gmatch("[^\n]+") do
    local id, text = line:match("^([^|]+)|(.+)$")
    if id and text then
      Game.achievements.unlocked[id] = text
    end
  end
end

local function unlockAchievement(id, text)
  if Game.demoMode or Game.achievements.unlocked[id] then
    return
  end

  Game.achievements.unlocked[id] = text
  Game.achievements.events[#Game.achievements.events + 1] = { id = id, text = text, ttl = 4 }
  saveAchievements()
  setMessage("SIGNAL LOGGED: " .. string.upper(id), 1.7)
end

Game.unlockAchievement = unlockAchievement

function Game.setDemoMode(enabled)
  Game.demoMode = enabled and true or false
  Game.maxDecks = Game.demoMode and min(2, Level.maxDecks) or Level.maxDecks
end

local function deckSeed(seed, deck)
  return seed + deck * 1000003
end

local startDeck

local incidentDefs = {
  blackout = {
    label = "BLACKOUT",
    signal = "dark_pulse",
  },
  flood_surge = {
    label = "FLOOD SURGE",
    signal = "wet_tracks",
  },
  vent_bloom = {
    label = "VENT BLOOM",
    signal = "vent_call",
  },
  heat_spike = {
    label = "HEAT SPIKE",
    signal = "ash_drift",
  },
  lockdown = {
    label = "LOCKDOWN",
    signal = "seal_mark",
  },
  nest_wake = {
    label = "NEST WAKE",
    signal = "alarm_mark",
  },
  faction_raid = {
    label = "FACTION RAID",
    signal = "trade_mark",
  },
}

local incidentDecks = {
  { "nest_wake", "blackout" },
  { "flood_surge", "vent_bloom", "lockdown" },
  { "heat_spike", "blackout", "nest_wake", "vent_bloom", "lockdown", "faction_raid" },
}

local appendIncidentLog

local function addSignal(kind, x, y, strength, ttl, source, discovered)
  if not Game.level then
    return nil
  end

  local signal = {
    kind = kind,
    x = x,
    y = y,
    strength = strength or 1,
    ttl = ttl,
    source = source or "ecology",
    discovered = discovered or false,
  }

  Game.level.signals = Game.level.signals or {}
  Game.level.signals[#Game.level.signals + 1] = signal
  return signal
end

Game.addSignal = addSignal

local function chooseIncident(deck)
  local profile = Game.level and Game.level.biomeProfile
  if profile and profile.incidents then
    local branchIncident = Game.level.branch and Game.level.branch.incident
    if branchIncident then
      return branchIncident
    end
    return profile.incidents[love.math.random(#profile.incidents)]
  end
  local list = incidentDecks[min(deck or 1, #incidentDecks)] or incidentDecks[1]
  return list[love.math.random(#list)]
end

local function signalCycleShelter(phase)
  if not phase or not phase.shelter or not Game.level.cycleShelters or #Game.level.cycleShelters == 0 then
    return
  end
  local shelter = Game.level.cycleShelters[love.math.random(#Game.level.cycleShelters)]
  addSignal("shelter_mark", shelter.x + 0.5, shelter.y + 0.5, 1.5, 18, "cycle", true)
end

local function setCyclePhase(index, opening)
  local phase = Cycles.phaseAt(index)
  local biome = Game.level.biomeProfile and Game.level.biomeProfile.district
  local incident = Cycles.incidentFor(biome, phase.id, chooseIncident(Game.deck))
  local duration = Cycles.durationFor(phase)
  local pulseEvery = phase.pulseEvery or 0

  Game.ecology.cycle = {
    index = index,
    phase = phase.id,
    label = phase.label,
    duration = duration,
    timer = duration,
    pulseEvery = pulseEvery,
    pulse = pulseEvery > 0 and min(pulseEvery, 2.5 + love.math.random() * 1.5) or 999,
    pressure = phase.pressure or 0,
  }
  Game.ecology.active = incident
  Game.ecology.timer = duration
  Game.ecology.pulse = Game.ecology.cycle.pulse

  if phase.signal then
    addSignal(phase.signal, Game.player.x, Game.player.y, 1.2, 16, "cycle", true)
  end
  signalCycleShelter(phase)

  local def = incidentDefs[incident]
  if def then
    addSignal(def.signal, Game.level.start.x + 0.5, Game.level.start.y + 0.5, 1.1, opening and nil or 20, "cycle", opening)
  end
  if appendIncidentLog then
    appendIncidentLog("CYCLE: " .. phase.label .. " / " .. string.upper(incident))
  end
  setMessage((opening and "CYCLE " or "CYCLE SHIFT: ") .. phase.label, 1.6)
end

local function initEcology()
  local primary = chooseIncident(Game.deck)
  local secondary = chooseIncident(min(Game.deck + 1, #incidentDecks))
  if secondary == primary then
    secondary = "nest_wake"
  end

  Game.ecology = {
    primary = primary,
    secondary = secondary,
    active = primary,
    intensity = 0.32 + (Game.deck or 1) * 0.18,
    timer = 0,
    pulse = 0,
    blackout = 0,
    flood = 0,
    heat = 0,
    lockdown = 0,
    ventBloom = 0,
    nestWake = 0,
    raid = 0,
    cycle = nil,
    observed = {},
  }

  setCyclePhase(1, true)
end

function appendIncidentLog(text)
end

local function nearestNest()
  local best
  local bestDistance = math.huge

  for _, nest in ipairs(Game.level.nests or {}) do
    local dx = nest.x + 0.5 - Game.player.x
    local dy = nest.y + 0.5 - Game.player.y
    local distance = dx * dx + dy * dy
    if distance < bestDistance then
      best = nest
      bestDistance = distance
    end
  end

  return best
end

local function alarmFaction(name, amount, x, y, source)
  if not name then
    return
  end

  for _, faction in ipairs(Game.level.factions or {}) do
    if faction.name == name then
      faction.alarm = max(faction.alarm or 0, amount or 4)
      addSignal("alarm_mark", x or Game.player.x, y or Game.player.y, 1.1 + (amount or 4) * 0.05, 18, source or name)
      for _, nest in ipairs(Game.level.nests or {}) do
        if nest.faction == name then
          nest.alarm = max(nest.alarm or 0, amount or 4)
        end
      end
      return
    end
  end
end

local function randomGate()
  if not Game.level.gates or #Game.level.gates == 0 then
    return nil
  end
  return Game.level.gates[love.math.random(#Game.level.gates)]
end

local function pulseIncident(kind)
  local ecology = Game.ecology
  local def = incidentDefs[kind]
  if not ecology or not def then
    return
  end

  ecology.active = kind
  ecology.observed[kind] = true
  unlockAchievement("incident_contact", "Witness a live facility incident.")

  if kind == "blackout" then
    ecology.blackout = 5.5 + ((ecology.cycle and ecology.cycle.pressure) or 0) * 2
    addSignal("dark_pulse", Game.player.x, Game.player.y, 1.2, 18, "facility", true)
    appendIncidentLog("BLACKOUT: LOCAL LIGHT UNRELIABLE")
  elseif kind == "flood_surge" then
    ecology.flood = 7 + ((ecology.cycle and ecology.cycle.pressure) or 0) * 3
    addSignal("wet_tracks", Game.player.x, Game.player.y, 1.1, 22, "facility", true)
    addSignal("surge_line", Game.player.x, Game.player.y, 1.2, 18, "facility", true)
    appendIncidentLog("FLOOD SURGE: PUMPS RECOMMENDED")
  elseif kind == "vent_bloom" then
    ecology.ventBloom = 8 + ((ecology.cycle and ecology.cycle.pressure) or 0) * 2
    local vent = Game.level.exit or { x = Game.player.x, y = Game.player.y }
    Actor.emitNoise(Game, vent.x + 0.5, vent.y + 0.5, 3.5, 1.4, "vent")
    addSignal("vent_call", vent.x + 0.5, vent.y + 0.5, 1.2, 20, "facility")
    appendIncidentLog("VENT BLOOM: SOUND CARRIERS ACTIVE")
  elseif kind == "heat_spike" then
    ecology.heat = 8 + ((ecology.cycle and ecology.cycle.pressure) or 0) * 3
    addSignal("ash_drift", Game.player.x, Game.player.y, 1.1, 22, "facility", true)
    addSignal("smoke_veil", Game.player.x, Game.player.y, 1.1, 18, "facility", true)
    appendIncidentLog("HEAT SPIKE: VENTS OR PUMPS ADVISED")
  elseif kind == "lockdown" then
    local gate = randomGate()
    if gate then
      local previousLocked = gate.cell.gateLocked
      gate.cell.gateLocked = true
      Game.effects[#Game.effects + 1] = { kind = "lockdown", x = gate.x + 0.5, y = gate.y + 0.5, ttl = 12, gate = gate, previousLocked = previousLocked }
      addSignal("seal_mark", gate.x + 0.5, gate.y + 0.5, 1.2, 14, "facility")
    end
    ecology.lockdown = 12
    appendIncidentLog("LOCKDOWN: ROUTE SEALED TEMPORARILY")
  elseif kind == "nest_wake" then
    local nest = nearestNest()
    if nest then
      nest.alarm = max(nest.alarm or 0, 8)
      addSignal("alarm_mark", nest.x + 0.5, nest.y + 0.5, 1.4, 24, nest.kind)
      Actor.emitNoise(Game, nest.x + 0.5, nest.y + 0.5, 2.8, 1.4, "alarm")
    end
    ecology.nestWake = 9
    appendIncidentLog("NEST WAKE: GUARDS MOVING")
  elseif kind == "faction_raid" then
    ecology.raid = 10
    local cache = Game.level.toolCaches and Game.level.toolCaches[love.math.random(max(1, #Game.level.toolCaches))]
    local x = cache and cache.x + 0.5 or Game.player.x
    local y = cache and cache.y + 0.5 or Game.player.y
    addSignal("trade_mark", x, y, 1.5, 24, "raid", true)
    Actor.emitNoise(Game, x, y, 3.0, 1.4, "raid")
    for _, faction in ipairs(Game.level.factions or {}) do
      faction.alarm = max(faction.alarm or 0, 6)
    end
    appendIncidentLog("FACTION RAID: CACHE ROUTES EXPOSED")
  end
end

local function updateSignals(dt)
  local signals = Game.level and Game.level.signals or {}
  for i = #signals, 1, -1 do
    local signal = signals[i]
    if signal.ttl then
      signal.ttl = signal.ttl - dt
      if signal.ttl <= 0 then
        table.remove(signals, i)
      end
    end
  end

  local surveyActive = Game.survey and Game.survey.ttl > 0
  for _, signal in ipairs(signals) do
    local dx = signal.x - Game.player.x
    local dy = signal.y - Game.player.y
    if surveyActive or dx * dx + dy * dy < 12.25 then
      if not signal.discovered then
        signal.discovered = true
        unlockAchievement("first_signal", "Identify an ecology signal in-world.")
      end
    end
  end

  for _, creature in ipairs(Game.creatures or {}) do
    if creature.alive then
      creature.trackTimer = max(0, (creature.trackTimer or 0) - dt)
      if creature.trackTimer <= 0 then
        addSignal("track", creature.x, creature.y, creature.kind == "hunter" and 1.4 or 1, 20, creature.kind)
        creature.trackTimer = creature.kind == "skitter" and 2.8 or 1.7
      end
    end
  end
end

local function updateEcology(dt)
  if not Game.ecology then
    return
  end

  local ecology = Game.ecology
  ecology.blackout = max(0, (ecology.blackout or 0) - dt)
  ecology.flood = max(0, (ecology.flood or 0) - dt)
  ecology.heat = max(0, (ecology.heat or 0) - dt)
  ecology.lockdown = max(0, (ecology.lockdown or 0) - dt)
  ecology.ventBloom = max(0, (ecology.ventBloom or 0) - dt)
  ecology.nestWake = max(0, (ecology.nestWake or 0) - dt)
  ecology.raid = max(0, (ecology.raid or 0) - dt)
  if ecology.cycle then
    ecology.cycle.timer = max(0, (ecology.cycle.timer or 0) - dt)
    ecology.cycle.pulse = max(0, (ecology.cycle.pulse or 0) - dt)
    ecology.timer = ecology.cycle.timer
    ecology.pulse = ecology.cycle.pulse
  else
    ecology.timer = max(0, (ecology.timer or 0) - dt)
    ecology.pulse = max(0, (ecology.pulse or 0) - dt)
  end
  for _, faction in ipairs(Game.level.factions or {}) do
    faction.alarm = max(0, (faction.alarm or 0) - dt * 0.45)
  end
  Game.survey.ttl = max(0, (Game.survey.ttl or 0) - dt)
  Game.toolWheel.timer = max(0, (Game.toolWheel.timer or 0) - dt)
  if Game.toolWheel.timer <= 0 then
    Game.toolWheel.visible = false
  end

  for i = #(Game.achievements.events or {}), 1, -1 do
    local event = Game.achievements.events[i]
    event.ttl = max(0, (event.ttl or 0) - dt)
    if event.ttl <= 0 then
      table.remove(Game.achievements.events, i)
    end
  end

  if ecology.cycle and ecology.cycle.pulseEvery > 0 and ecology.cycle.pulse <= 0 then
    pulseIncident(ecology.active or ecology.primary)
    ecology.cycle.pulse = ecology.cycle.pulseEvery + love.math.random() * 2
    ecology.pulse = ecology.cycle.pulse
  elseif not ecology.cycle and ecology.pulse <= 0 then
    pulseIncident(ecology.active or ecology.primary)
    ecology.pulse = 13 + love.math.random() * 8
  end

  if ecology.cycle and ecology.cycle.timer <= 0 then
    setCyclePhase((ecology.cycle.index or 1) + 1, false)
  elseif not ecology.cycle and ecology.timer <= 0 then
    ecology.active = ecology.active == ecology.primary and ecology.secondary or ecology.primary
    ecology.timer = 24 + love.math.random() * 16
    local def = incidentDefs[ecology.active]
    if def then
      setMessage("INCIDENT SHIFT: " .. def.label, 1.7)
    end
  end

  updateSignals(dt)
end

function startDeck(deck)
  Game.deck = deck
  love.math.setRandomSeed(deckSeed(Game.seed, deck))

  Game.level = Level.generate(nil, nil, deck, nil)
  Game.player = Actor.createPlayer(Game.level)
  Game.creatures = Actor.createCreatures(Game.level)
  Game.npcs = Actor.createNPCs(Game.level)
  Game.enemy = Actor.nearestThreat(Game) or Game.creatures[1] or Actor.createEnemy(Game.level)
  Game.state = "playing"
  Game.keys = { total = #Game.level.keys, collected = 0, small = 0, exit = false }
  Game.loopTimer = Game.loopDuration
  Game.respawn = { x = Game.player.x, y = Game.player.y }
  Game.level.visitedMap = {}
  Game.conversation = { active = false, npc = nil, topics = {}, index = 1, response = "" }
  Game.noise = { ttl = 0, intensity = 0, radius = 0, x = 0, y = 0 }
  Game.noises = {}
  Game.effects = {}
  Game.props = {}
  Game.survey = { ttl = 0 }
  Game.toolWheel = { visible = false, timer = 0 }
  Game.mapHeld = false
  Game.mapGamepadHeld = false
  Game.statusHeld = false
  Game.statusGamepadHeld = false
  Game.hazardTimer = 0
  Game.seedEntry.active = false
  Game.seedEntry.text = ""
  Game.paused = false
  Game.bindTarget = nil
  initEcology()
  setMessage(string.format("FIND EXIT KEY  DECK %02d", Game.deck), 1.7)
  love.mouse.setRelativeMode(true)
end

local function startGame(seed)
  Game.seed = seed or newSeed()
  Game.lastSeed = Game.seed
  Game.deck = 1
  Game.maxDecks = Game.demoMode and min(2, Level.maxDecks) or Level.maxDecks
  Game.survivalTime = 0
  Game.torch = { fuel = 1 }
  Game.inventory = {
    selected = "flare",
    flare = 1,
    noisemaker = 1,
    scent = 1,
    snare = 0,
    pheromone = 1,
    probe = 1,
    oil = 1,
    beacon = 0,
    max = { flare = 3, noisemaker = 3, scent = 3, snare = 2, pheromone = 2, probe = 2, oil = 3, beacon = 2 },
  }
  startDeck(1)
end

local function advanceDeck()
  if Game.deck >= Game.maxDecks then
    Game.state = "escaped"
    Game.bestTime = max(Game.bestTime, Game.survivalTime)
    unlockAchievement("extraction", "Extract from Tikrit's active decks.")
    love.mouse.setRelativeMode(false)
    return
  end

  startDeck(Game.deck + 1)
end

local function resetLife(reason)
  local respawn = Game.respawn or { x = Game.level.start.x + 0.5, y = Game.level.start.y + 0.5 }

  Game.player = Actor.createPlayer(Game.level)
  Game.player.x = respawn.x
  Game.player.y = respawn.y
  Game.player.floorZ = Actor.floorAt(Game.level, respawn.x, respawn.y)
  Game.player.eyeZ = Game.player.floorZ + (Game.player.eyeHeight or Actor.eyeHeight)
  Game.creatures = Actor.createCreatures(Game.level)
  Game.npcs = Actor.createNPCs(Game.level)
  Game.enemy = Actor.nearestThreat(Game) or Game.creatures[1] or Actor.createEnemy(Game.level)
  Game.noise = { ttl = 0, intensity = 0, radius = 0, x = 0, y = 0 }
  Game.noises = {}
  Game.effects = {}
  Game.props = {}
  Game.survey = { ttl = 0 }
  Game.conversation = { active = false, npc = nil, topics = {}, index = 1, response = "" }
  Game.loopTimer = Game.loopDuration
  Game.torch.fuel = 1
  Game.inventory.flare = 1
  Game.inventory.noisemaker = 1
  Game.inventory.scent = 1
  Game.inventory.snare = 0
  Game.inventory.pheromone = 1
  Game.inventory.probe = 1
  Game.inventory.oil = 1
  Game.inventory.beacon = 0
  Game.state = "playing"
  love.mouse.setRelativeMode(true)
  setMessage(reason or "WAKE UP", 1.2)
end

Game.resetLife = resetLife

local function updateMapDiscovery()
  if not Game.level or not Game.player then
    return
  end

  Game.level.visitedMap = Game.level.visitedMap or {}
  local px = floor(Game.player.x)
  local py = floor(Game.player.y)
  local radius = (Game.survey and Game.survey.ttl > 0) and 5 or 2

  for y = py - radius, py + radius do
    for x = px - radius, px + radius do
      if abs(x - px) + abs(y - py) <= radius and Level.isWalkableCell(Game.level, x, y) then
        Game.level.visitedMap[U.keyOf(x, y)] = true
      end
    end
  end
end

local function updateLoopTimer(dt)
  if Game.state ~= "playing" or Game.seedEntry.active or Game.paused then
    return
  end

  Game.loopTimer = max(0, (Game.loopTimer or Game.loopDuration) - dt)
  if Game.loopTimer <= 0 then
    resetLife("TIME")
  end
end

local function updateNoise(dt)
  local strongest = nil

  for i = #(Game.noises or {}), 1, -1 do
    local noise = Game.noises[i]
    noise.ttl = max(0, (noise.ttl or 0) - dt)
    noise.intensity = (noise.intensity or 0) * (1 - U.clamp(dt * 1.7, 0, 1))
    if noise.ttl <= 0 or noise.intensity <= 0.03 then
      table.remove(Game.noises, i)
    elseif not strongest or noise.intensity > strongest.intensity then
      strongest = noise
    end
  end

  Game.noise = strongest or { ttl = 0, intensity = 0, radius = 0, x = 0, y = 0 }
end

local function updateEffects(dt)
  for i = #(Game.effects or {}), 1, -1 do
    local effect = Game.effects[i]
    effect.ttl = max(0, (effect.ttl or 0) - dt)
    effect.pulse = max(0, (effect.pulse or 0) - dt)

    if effect.kind == "flare" and effect.pulse <= 0 then
      Actor.emitNoise(Game, effect.x, effect.y, 1.5, 0.8, "flare")
      effect.pulse = 1.4
    elseif effect.kind == "lockdown" and effect.gate and effect.ttl <= 0 then
      effect.gate.cell.gateLocked = effect.previousLocked or false
    end

    if effect.ttl <= 0 then
      table.remove(Game.effects, i)
    end
  end

  local decoy = Game.level.systems and Game.level.systems.decoy
  if decoy and decoy.powered then
    decoy.cooldown = max(0, (decoy.cooldown or 0) - dt)
    if decoy.cooldown <= 0 then
      local target = Game.level.exit or { x = Game.player.x, y = Game.player.y }
      Actor.emitNoise(Game, target.x + 0.5, target.y + 0.5, 3.4, 1.2, "decoy")
      Game.torch.fuel = U.clamp(Game.torch.fuel - 0.03, 0, 1)
      decoy.cooldown = 3.4
    end
  end
end

local function updateProps(dt)
  for i = #(Game.props or {}), 1, -1 do
    local prop = Game.props[i]
    prop.ttl = max(0, (prop.ttl or 0) - dt)
    prop.pulse = max(0, (prop.pulse or 0) - dt)

    if prop.pulse <= 0 then
      if prop.kind == "scent" then
        Actor.emitNoise(Game, prop.x, prop.y, 1.8, 1.4, "scent")
        prop.pulse = 2.0
      elseif prop.kind == "noisemaker" then
        Actor.emitNoise(Game, prop.x, prop.y, 3.2, 1.1, "noisemaker")
        prop.pulse = 1.15
      elseif prop.kind == "pheromone" then
        addSignal("pheromone", prop.x, prop.y, 1.3, 6, "player", true)
        prop.pulse = 5.5
      elseif prop.kind == "probe" then
        addSignal("survey_ping", prop.x, prop.y, 1.1, 8, "player", true)
        prop.pulse = 3.4
      elseif prop.kind == "beacon" then
        addSignal("trade_mark", prop.x, prop.y, 1.4, 9, "player", true)
        Actor.emitNoise(Game, prop.x, prop.y, 3.8, 1.2, "beacon")
        prop.pulse = 1.8
      end
    end

    if prop.ttl <= 0 then
      table.remove(Game.props, i)
    end
  end
end

local function playerInShelter()
  local cell = Level.cellAtWorld(Game.level, Game.player.x, Game.player.y)
  return cell and cell.shelter
end

local function updateTorch(dt)
  local drain = 0.010

  if Game.player.sprinting then
    drain = drain + 0.004
  end

  if Game.enemy and Game.enemy.visible then
    drain = drain + 0.002
  end

  if Game.level.systems and Game.level.systems.lights.powered then
    drain = drain * 0.8
  end

  if Game.ecology and Game.ecology.blackout > 0 then
    drain = drain + 0.008
  end
  if Game.ecology and Game.ecology.cycle then
    local pressure = Game.ecology.cycle.pressure or 0
    drain = drain + (playerInShelter() and pressure * 0.002 or pressure * 0.008)
  end

  local biome = Game.level.biomeProfile and Game.level.biomeProfile.district
  if biome == "cryo_vault" and not (Game.level.systems and Game.level.systems.vents.powered) then
    drain = drain + 0.004
  elseif biome == "reactor_trench" and not (Game.level.systems and (Game.level.systems.vents.powered or Game.level.systems.pumps.powered)) then
    drain = drain + 0.012
  elseif biome == "fungal_service" and Game.player.sprinting then
    drain = drain + 0.003
  elseif biome == "storm_drain" and not (Game.level.systems and Game.level.systems.pumps.powered) then
    drain = drain + 0.006
  elseif biome == "ash_foundry" and not (Game.level.systems and Game.level.systems.vents.powered) then
    drain = drain + 0.01
  elseif biome == "signal_catacombs" and not (Game.survey and Game.survey.ttl > 0) then
    drain = drain + 0.003
  elseif biome == "organ_machine" and Game.level.systems and Game.level.systems.doors.powered then
    drain = drain + 0.004
  end

  Game.torch.fuel = U.clamp(Game.torch.fuel - dt * drain, 0, 1)
end

local function updateHazards(dt)
  Game.hazardTimer = max(0, (Game.hazardTimer or 0) - dt)

  local cell = Level.cellAtWorld(Game.level, Game.player.x, Game.player.y)
  if not cell or not Level.isHazardActive(cell) then
    return
  end

  local drain = cell.hazard.kind == "ember" and 0.055 or (cell.hazard.kind == "wire" and 0.038 or 0.026)
  if cell.hazard.kind == "wire" and cell.terrain == "water" then
    drain = drain + 0.028
  end
  if Game.ecology then
    if cell.hazard.kind == "wire" and Game.ecology.flood > 0 then
      drain = drain + 0.024
    elseif cell.hazard.kind == "ember" and Game.ecology.heat > 0 then
      drain = drain + 0.032
    end
    if Game.ecology.cycle then
      drain = drain + (Game.ecology.cycle.pressure or 0) * 0.012
    end
  end
  if playerInShelter() then
    drain = drain * 0.65
  end
  local biome = Game.level.biomeProfile and Game.level.biomeProfile.district
  if biome == "reactor_trench" and cell.hazard.kind == "ember" then
    drain = drain + (Game.level.systems and Game.level.systems.vents.powered and -0.018 or 0.026)
  elseif biome == "waste_artery" and cell.hazard.kind == "wire" then
    drain = drain + (Game.level.systems and Game.level.systems.pumps.powered and -0.016 or 0.024)
  elseif biome == "cryo_vault" and cell.hazard.kind == "pit" then
    drain = drain + 0.016
  elseif biome == "storm_drain" and cell.hazard.kind == "wire" then
    drain = drain + (Game.level.systems and Game.level.systems.pumps.powered and -0.012 or 0.032)
  elseif biome == "ash_foundry" and cell.hazard.kind == "ember" then
    drain = drain + (Game.level.systems and Game.level.systems.vents.powered and -0.014 or 0.03)
  elseif biome == "organ_machine" and cell.hazard.kind == "wire" then
    drain = drain + (Game.level.systems and Game.level.systems.doors.powered and 0.018 or 0)
  end
  drain = max(0.01, drain)
  Game.torch.fuel = U.clamp(Game.torch.fuel - dt * drain, 0, 1)

  if Game.hazardTimer <= 0 then
    setMessage(string.upper(cell.hazard.kind), 1.1)
    Game.hazardTimer = 2.4
  end
end

local function distanceToPlayer(x, y)
  local dx = x - Game.player.x
  local dy = y - Game.player.y
  return math.sqrt(dx * dx + dy * dy)
end

local function npcAtPlayer(maxDistance)
  local best
  local bestDistance = maxDistance or 2.05

  for _, npc in ipairs(Game.npcs or {}) do
    if npc.alive then
      local distance = distanceToPlayer(npc.x, npc.y)
      local sameFloor = abs((npc.floorZ or 0) - (Game.player.floorZ or 0)) < 0.8
      if sameFloor and distance < bestDistance and (distance < 1.2 or Level.lineOfSight(Game.level, Game.player.x, Game.player.y, npc.x, npc.y)) then
        best = npc
        bestDistance = distance
      end
    end
  end

  return best, bestDistance
end

function Game.nearNPC()
  if not Game.level or not Game.player then
    return nil
  end

  return npcAtPlayer()
end

local function nearestItem(items, predicate)
  local best
  local bestDistance = math.huge

  for _, item in ipairs(items or {}) do
    if not predicate or predicate(item) then
      local distance = distanceToPlayer((item.x or 0) + 0.5, (item.y or 0) + 0.5)
      if distance < bestDistance then
        best = item
        bestDistance = distance
      end
    end
  end

  return best, bestDistance
end

local function directionToCell(x, y)
  local path = Level.findPath(Game.level, floor(Game.player.x), floor(Game.player.y), x, y)
  local targetX = x + 0.5
  local targetY = y + 0.5

  if path[1] then
    targetX = path[1].x
    targetY = path[1].y
  end

  local dx = targetX - Game.player.x
  local dy = targetY - Game.player.y
  local direction

  if abs(dx) > abs(dy) then
    direction = dx >= 0 and "east" or "west"
  else
    direction = dy >= 0 and "south" or "north"
  end

  local distance = distanceToPlayer(x + 0.5, y + 0.5)
  if distance < 1.4 then
    return "right here"
  end
  return string.format("%s, about %dm", direction, floor(distance + 0.5))
end

local function topicTarget(item)
  if not item then
    return nil
  end

  return { x = (item.x or Game.player.x) + 0.5, y = (item.y or Game.player.y) + 0.5 }
end

local function routeTopic()
  local level = Game.level

  if Game.keys.collected < Game.keys.total then
    local key = nearestItem(level.keys, function(item)
      return item.cell and item.cell.key and not item.cell.key.collected
    end)
    if key then
      return {
        id = "route",
        label = "Route",
        response = "A key is " .. directionToCell(key.x, key.y) .. ". Grab it before relying on locked shortcuts.",
        target = topicTarget(key),
        lead = true,
      }
    end
  end

  if level.exit then
    return {
      id = "route",
      label = "Route",
      response = "Extraction is the exit shaft " .. directionToCell(level.exit.x, level.exit.y) .. ". You need the exit key before it opens.",
      target = topicTarget(level.exit),
      lead = true,
    }
  end

  return { id = "route", label = "Route", response = "I do not have a clean route read on this deck yet." }
end

local function exitTopic()
  local level = Game.level
  if level.exit then
    local state = Game.keys.exit and "You have the exit key." or "You still need the exit key."
    return {
      id = "exit",
      label = "Exit",
      response = state .. " The exit is " .. directionToCell(level.exit.x, level.exit.y) .. ".",
      target = topicTarget(level.exit),
      lead = true,
    }
  end

  return { id = "exit", label = "Exit", response = "No exit read from here. Follow the widest route." }
end

local function keyTopic()
  local key = nearestItem(Game.level.keys, function(item)
    return item.cell and item.cell.key and not item.cell.key.collected
  end)

  if key then
    local label = key.kind == "exit" and "exit key" or "small key"
    return {
      id = "key",
      label = "Key",
      response = "The nearest " .. label .. " is " .. directionToCell(key.x, key.y) .. ". Small keys open nearby shortcuts with F.",
      target = topicTarget(key),
      lead = true,
    }
  end

  return {
    id = "key",
    label = "Key",
    response = string.format("Keys held: exit %s, small %d.", Game.keys.exit and "yes" or "no", Game.keys.small or 0),
  }
end

local function shelterTopic()
  local shelter = nearestItem(Game.level.cycleShelters, function(item)
    return item.cell and item.cell.shelter
  end)

  if shelter then
    return {
      id = "shelter",
      label = "Shelter",
      response = "The nearest shelter is " .. directionToCell(shelter.x, shelter.y) .. ". Step onto it to reset your wake point and refill time.",
      target = topicTarget(shelter),
      lead = true,
    }
  end

  return { id = "shelter", label = "Shelter", response = "I do not see a shelter mark nearby. Keep moving and watch for safe floor marks." }
end

local function threatTopic()
  local threat, distance = Actor.nearestThreat(Game)
  if not threat then
    return { id = "threat", label = "Threat", response = "No major threat has the deck center right now. Listen for sudden noise chains." }
  end

  local advice = NPCContent.creatureAdvice[threat.kind] or "Break sight, reduce noise, and force it around terrain."
  return {
    id = "threat",
    label = "Threat",
    response = string.format("%s pressure is about %dm out and currently %s. %s", string.upper(threat.kind or "threat"), floor((distance or 0) + 0.5), string.upper(threat.state or "moving"), advice),
  }
end

local function biomeTopic()
  local level = Game.level
  local profile = level.biomeProfile or {}
  local biome = profile.district
  local incident = Game.ecology and Game.ecology.active or level.branch and level.branch.incident or "quiet"
  local advice = NPCContent.biomeAdvice[biome] or (profile.risk and ("Watch for " .. profile.risk .. ".") or "Read terrain before sprinting.")
  local cycle = Game.ecology and Game.ecology.cycle
  local pressureText = cycle and (" The area is in " .. string.upper(cycle.label or cycle.phase or "pressure") .. " pressure.") or ""
  return {
    id = "biome",
    label = "Biome",
    response = string.format("%s: %s Active pressure is %s.%s", profile.label or "UNKNOWN", advice, string.upper(incident or "quiet"), pressureText),
  }
end

local function toolsTopic()
  local selected = Game.inventory.selected or "flare"
  local count = Game.inventory[selected] or 0
  local advice = NPCContent.toolAdvice[selected] or "Use tools to redirect pressure instead of trying to outrun everything."
  local cache = nearestItem(Game.level.toolCaches, function(item)
    return item.cell and item.cell.tool and not item.cell.toolUsed
  end)
  local cacheText = ""

  if cache then
    local kind = cache.cell.tool and cache.cell.tool.kind or "tool"
    cacheText = " Nearest cache is " .. string.upper(kind) .. " " .. directionToCell(cache.x, cache.y) .. "."
  end

  return {
    id = "tools",
    label = "Tools",
    response = string.format("%s x%d. %s%s", string.upper(selected), count, advice, cacheText),
    target = cache and topicTarget(cache) or nil,
    lead = cache ~= nil,
  }
end

local topicBuilders = {
  route = routeTopic,
  exit = exitTopic,
  key = keyTopic,
  shelter = shelterTopic,
  threat = threatTopic,
  biome = biomeTopic,
  tools = toolsTopic,
}

local function buildConversationTopics(npc)
  local profile = NPCContent.profiles[npc.kind] or NPCContent.profiles.scout
  local topics = {}
  local seen = {}

  for _, id in ipairs(profile.topics or {}) do
    local builder = topicBuilders[id]
    if builder and not seen[id] then
      topics[#topics + 1] = builder()
      seen[id] = true
    end
    if #topics >= 4 then
      break
    end
  end

  for _, id in ipairs({ "exit", "key", "threat", "shelter", "tools", "biome" }) do
    if #topics >= 2 then
      break
    end
    local builder = topicBuilders[id]
    if builder and not seen[id] then
      topics[#topics + 1] = builder()
      seen[id] = true
    end
  end

  return topics
end

local function openConversation()
  local npc = npcAtPlayer()
  if not npc then
    return false
  end

  npc.talking = true
  npc.path = {}
  Game.conversation = {
    active = true,
    npc = npc,
    topics = buildConversationTopics(npc),
    index = 1,
    response = string.format("%s here. Ask for the deck read.", npc.callsign or "GUIDE"),
  }
  love.mouse.setRelativeMode(false)
  return true
end

local function nearbyLockedDoor()
  local px = floor(Game.player.x)
  local py = floor(Game.player.y)
  local best
  local bestDistance = 2.1

  for _, lock in ipairs(Game.level.locks or {}) do
    if lock.cell and lock.cell.lock and lock.cell.lock.locked then
      local distance = abs(lock.x - px) + abs(lock.y - py)
      if distance < bestDistance then
        best = lock
        bestDistance = distance
      end
    end
  end

  for _, gate in ipairs(Game.level.gates or {}) do
    if gate.cell and gate.cell.gateLocked then
      local distance = abs(gate.x - px) + abs(gate.y - py)
      if distance < bestDistance then
        best = gate
        bestDistance = distance
      end
    end
  end

  return best
end

local function unlockNearbyDoor()
  local door = nearbyLockedDoor()
  if not door then
    return false
  end

  if (Game.keys.small or 0) <= 0 then
    setMessage("SMALL KEY NEEDED", 1)
    return true
  end

  Game.keys.small = max(0, (Game.keys.small or 0) - 1)
  if door.cell.lock then
    door.cell.lock.locked = false
  end
  door.cell.gateLocked = false
  door.cell.light = 0.72
  setMessage("SHORTCUT OPEN", 1.1)
  Audio.relay()
  return true
end

local function closeConversation()
  if Game.conversation and Game.conversation.npc then
    Game.conversation.npc.talking = false
  end
  Game.conversation = { active = false, npc = nil, topics = {}, index = 1, response = "" }
  if Game.state == "playing" then
    love.mouse.setRelativeMode(true)
  end
end

local function moveConversationCursor(delta)
  local count = #(Game.conversation and Game.conversation.topics or {})
  if count <= 0 then
    return
  end
  Game.conversation.index = U.clamp((Game.conversation.index or 1) + delta, 1, count)
end

local function chooseConversationTopic()
  local convo = Game.conversation or {}
  local topic = convo.topics and convo.topics[convo.index or 1]
  local npc = convo.npc

  if not topic then
    return
  end

  convo.response = topic.response
  convo.responseTopic = topic.id
  if npc and topic.lead and topic.target then
    npc.leadTarget = { x = topic.target.x, y = topic.target.y, ttl = 10 }
    convo.response = convo.response .. " Close comms and I will guide partway."
  end
end

local function openInteraction()
  if Game.conversation.active then
    return
  end

  if openConversation() then
    return
  end

  if unlockNearbyDoor() then
    return
  end

  setMessage("NO CONTACT", 0.8)
end

local toolOrder = { "flare", "noisemaker", "scent", "snare", "pheromone", "probe", "oil", "beacon" }

local function addInventory(kind, amount)
  local maxCount = Game.inventory.max[kind] or 0
  if maxCount <= 0 then
    return false
  end

  local before = Game.inventory[kind] or 0
  Game.inventory[kind] = U.clamp(before + (amount or 1), 0, maxCount)
  return Game.inventory[kind] > before
end

local function spawnCreature(kind, x, y, faction)
  local creature = Actor.createCreature(Game.level, kind, {
    x = floor(x or Game.player.x),
    y = floor(y or Game.player.y),
    faction = faction,
  }, #(Game.creatures or {}) + 1)
  creature.awake = true
  creature.dormant = false
  creature.grace = 0
  Game.creatures[#Game.creatures + 1] = creature
  Game.enemy = Actor.nearestThreat(Game) or creature
  return creature
end

local function checkInteractions()
  local cell = Level.cellAtWorld(Game.level, Game.player.x, Game.player.y)

  if not cell then
    return
  end

  if cell.key and not cell.key.collected then
    cell.key.collected = true
    Game.keys.collected = Game.keys.collected + 1
    if cell.key.kind == "exit" then
      Game.keys.exit = true
      setMessage("EXIT KEY", 1.6)
    else
      Game.keys.small = (Game.keys.small or 0) + 1
      setMessage("SMALL KEY", 1.4)
    end
    Audio.refill()
  end

  if cell.shelter and (not Game.respawn or math.floor(Game.respawn.x) ~= math.floor(Game.player.x) or math.floor(Game.respawn.y) ~= math.floor(Game.player.y)) then
    Game.respawn = { x = math.floor(Game.player.x) + 0.5, y = math.floor(Game.player.y) + 0.5 }
    Game.loopTimer = Game.loopDuration
    setMessage("SHELTER SET", 1.2)
  end

  if cell.refill and not cell.refillUsed then
    cell.refillUsed = true
    if not addInventory("oil", 1) then
      Game.torch.fuel = U.clamp(Game.torch.fuel + 0.3, 0, 1)
    end
    Audio.refill()
    setMessage("OIL CACHE", 1.8)
  end

  if cell.tool and not cell.toolUsed then
    if cell.tool.mimic then
      cell.toolUsed = true
      cell.salvage = false
      spawnCreature("mimic", Game.player.x + math.cos(Game.player.angle) * 1.2, Game.player.y + math.sin(Game.player.angle) * 1.2, cell.faction)
      Actor.emitNoise(Game, Game.player.x, Game.player.y, 3.0, 1.2, "mimic")
      setMessage("FALSE CACHE", 1.4)
    else
      cell.toolUsed = true
      addInventory(cell.tool.kind, 1)
      alarmFaction(cell.faction, 4, Game.player.x, Game.player.y, "cache")
      Audio.refill()
      setMessage(string.upper(cell.tool.kind) .. " CACHE", 1.5)
    end
  end

  if cell.exit then
    if Game.keys.exit then
      advanceDeck()
    else
      setMessage("EXIT KEY NEEDED", 1.2)
    end
  end
end

local function dropPoint(distance)
  local x = Game.player.x + math.cos(Game.player.angle) * (distance or 1.5)
  local y = Game.player.y + math.sin(Game.player.angle) * (distance or 1.5)
  local cell = Level.cellAtWorld(Game.level, x, y)

  if not cell or Level.isBlocked(cell) then
    return Game.player.x, Game.player.y
  end

  return x, y
end

local function useSelectedTool()
  local tool = Game.inventory.selected
  local biome = Game.level.biomeProfile and Game.level.biomeProfile.district
  if (Game.inventory[tool] or 0) <= 0 then
    setMessage("NO " .. string.upper(tool), 0.9)
    return
  end

  if tool == "oil" then
    Game.inventory.oil = Game.inventory.oil - 1
    Game.torch.fuel = U.clamp(Game.torch.fuel + 0.45, 0, 1)
    Audio.refill()
    setMessage("OIL USED", 1.1)
    return
  end

  local x, y = dropPoint(1.8)
  Game.inventory[tool] = Game.inventory[tool] - 1

  if tool == "flare" then
    Game.effects[#Game.effects + 1] = { kind = "flare", x = x, y = y, ttl = 9, radius = 8.5, pulse = 0 }
    Game.props[#Game.props + 1] = { kind = "flare", x = x, y = y, ttl = 9, pulse = 0 }
    Actor.emitNoise(Game, x, y, 1.8, 1.2, "flare")
    if biome == "cryo_vault" then
      addSignal("frost_trace", x, y, 1.6, 18, "flare", true)
      Game.survey.ttl = max(Game.survey.ttl or 0, 5)
    end
    setMessage("FLARE BURNING", 1.2)
  elseif tool == "noisemaker" then
    Game.props[#Game.props + 1] = { kind = "noisemaker", x = x, y = y, ttl = 8, pulse = 0 }
    setMessage("NOISEMAKER ARMED", 1.2)
  elseif tool == "scent" then
    Game.props[#Game.props + 1] = { kind = "scent", x = x, y = y, ttl = 28, pulse = 0, scent = "player" }
    if biome == "fungal_service" then
      addSignal("spore_bloom", x, y, 1.5, 24, "player", true)
      Actor.emitNoise(Game, Game.player.x, Game.player.y, 2.6, 1.3, "spore")
    end
    setMessage("SCENT MARKER", 1.2)
  elseif tool == "snare" then
    Game.props[#Game.props + 1] = { kind = "snare", x = x, y = y, ttl = 30, armed = true }
    setMessage("SNARE WIRE", 1.2)
  elseif tool == "pheromone" then
    local ttl = biome == "fungal_service" and 48 or 34
    local strength = biome == "fungal_service" and 1.9 or 1.4
    Game.props[#Game.props + 1] = { kind = "pheromone", x = x, y = y, ttl = ttl, pulse = 0, scent = "territory" }
    addSignal("pheromone", x, y, strength, ttl, "player", true)
    local cell = Level.cellAtWorld(Game.level, x, y) or {}
    alarmFaction(cell.faction, biome == "fungal_service" and 7 or 4, x, y, "pheromone")
    setMessage("PHEROMONE BOUNDARY", 1.2)
  elseif tool == "probe" then
    Game.survey.ttl = 12
    Game.props[#Game.props + 1] = { kind = "probe", x = x, y = y, ttl = 12, pulse = 0 }
    addSignal("survey_ping", x, y, 1.2, 12, "player", true)
    setMessage("SURVEY PULSE", 1.2)
  elseif tool == "beacon" then
    Game.props[#Game.props + 1] = { kind = "beacon", x = x, y = y, ttl = 18, pulse = 0 }
    addSignal("trade_mark", x, y, 1.7, 20, "player", true)
    Actor.emitNoise(Game, x, y, 3.8, 1.4, "beacon")
    local cell = Level.cellAtWorld(Game.level, x, y) or {}
    local fallbackFaction = Game.level.factions and Game.level.factions[1] and Game.level.factions[1].name
    alarmFaction(cell.faction or fallbackFaction, 7, x, y, "beacon")
    setMessage("LURE BEACON", 1.2)
  end
end

local function selectToolByIndex(index)
  local tool = toolOrder[index]
  if tool then
    Game.inventory.selected = tool
    setMessage(string.upper(tool), 0.6)
  end
end

local function cycleTool()
  local current = 1
  for i, tool in ipairs(toolOrder) do
    if tool == Game.inventory.selected then
      current = i
      break
    end
  end
  selectToolByIndex((current % #toolOrder) + 1)
end

local function keyMatches(action, key)
  return key == actionKey(action)
end

local function togglePause()
  if Game.state ~= "playing" or Game.seedEntry.active or Game.conversation.active then
    return
  end
  Game.paused = not Game.paused
  Game.bindTarget = nil
  love.mouse.setRelativeMode(not Game.paused)
end

local function moveSettingsCursor(delta)
  Game.settingsIndex = U.clamp((Game.settingsIndex or 1) + delta, 1, #bindingActions)
end

local function beginBinding()
  Game.bindTarget = bindingActions[Game.settingsIndex or 1]
  setMessage("PRESS KEY FOR " .. string.upper(Game.bindTarget), 1.2)
end

local function resetBindings()
  Game.bindings = copyDefaultBindings()
  saveSettings()
  setMessage("DEFAULT CONTROLS", 1)
end

function Game.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  Game.fonts.hud = love.graphics.newFont(17)
  Game.fonts.title = love.graphics.newFont(58)
  Renderer.init()
  Audio.init()
  loadSettings()
  loadAchievements()
  startGame()
end

function Game.update(dt)
  dt = math.min(dt, 1 / 30)

  if Game.messageTimer > 0 then
    Game.messageTimer = max(0, Game.messageTimer - dt)
  end

  Audio.update(Game, dt)

  if Game.paused then
    return
  end

  if Game.state == "playing" and not Game.seedEntry.active then
    Game.survivalTime = Game.survivalTime + dt
    updateLoopTimer(dt)
    updateMapDiscovery()
    updateEcology(dt)
    updateNoise(dt)
    updateEffects(dt)
    updateProps(dt)
    if Game.conversation.active then
      for _, creature in ipairs(Game.creatures or {}) do
        creature.grace = max(creature.grace or 0, 0.65)
      end
    else
      Actor.updatePlayer(Game, dt, Audio)
    end
    Actor.updateNPCs(Game, dt)
    if Game.conversation.active then
      local npc = Game.conversation.npc
      if not npc or not npc.alive or distanceToPlayer(npc.x, npc.y) > 3.2 or npc.state == "flee" then
        closeConversation()
        setMessage("CONTACT BROKEN", 1)
      end
    end
    updateTorch(dt)
    updateHazards(dt)
    if not Game.conversation.active then
      checkInteractions()
    end
    Actor.updateCreatures(Game, dt, Audio)
  end
end

function Game.draw()
  Renderer.drawFrame(Game, function()
    Renderer.draw(Game)
    UI.draw(Game)
  end)
end

function Game.keypressed(key)
  if Game.bindTarget then
    Game.bindings[Game.bindTarget] = key
    Game.bindTarget = nil
    saveSettings()
    setMessage("CONTROL SAVED", 1)
    return
  end

  if Game.conversation.active then
    if key == "up" or key == "left" then
      moveConversationCursor(-1)
    elseif key == "down" or key == "right" or key == "tab" then
      moveConversationCursor(1)
    elseif key == "return" or key == "kpenter" or key == "space" then
      chooseConversationTopic()
    elseif keyMatches("interact", key) or key == "escape" then
      closeConversation()
    end
    return
  end

  if Game.seedEntry.active then
    if key == "return" or key == "kpenter" then
      local seed = tonumber(Game.seedEntry.text)
      if seed then
        startGame(seed)
      else
        Game.seedEntry.active = false
      end
    elseif key == "escape" then
      Game.seedEntry.active = false
    elseif key == "backspace" then
      Game.seedEntry.text = Game.seedEntry.text:sub(1, -2)
    end
    return
  end

  if Game.paused then
    if keyMatches("pause", key) then
      togglePause()
    elseif key == "up" then
      moveSettingsCursor(-1)
    elseif key == "down" then
      moveSettingsCursor(1)
    elseif key == "return" or key == "kpenter" then
      beginBinding()
    elseif key == "backspace" then
      resetBindings()
    end
    return
  end

  if keyMatches("pause", key) then
    togglePause()
  elseif keyMatches("map", key) then
    Game.mapHeld = true
  elseif keyMatches("status", key) then
    Game.statusHeld = true
  elseif key == "r" or (key == "space" and Game.state ~= "playing") then
    startGame(Game.lastSeed)
  elseif key == "n" then
    startGame()
  elseif key == "f2" then
    Game.seedEntry.active = true
    Game.seedEntry.text = tostring(Game.seed)
    love.mouse.setRelativeMode(false)
  elseif keyMatches("interact", key) and Game.state == "playing" then
    openInteraction()
  elseif keyMatches("cycleTool", key) and Game.state == "playing" then
    cycleTool()
    Game.toolWheel.visible = true
    Game.toolWheel.timer = 1.8
  elseif keyMatches("useTool", key) and Game.state == "playing" then
    useSelectedTool()
  elseif Game.state == "playing" and key:match("^[1-8]$") then
    selectToolByIndex(tonumber(key))
  elseif key == "x" then
    setMessage("RENDER " .. string.upper(Renderer.togglePost()), 0.8)
  end
end

function Game.textinput(text)
  if not Game.seedEntry.active then
    return
  end

  if text:match("^%d$") and #Game.seedEntry.text < 12 then
    Game.seedEntry.text = Game.seedEntry.text .. text
  end
end

function Game.keyreleased(key)
  if keyMatches("map", key) then
    Game.mapHeld = false
  elseif keyMatches("status", key) then
    Game.statusHeld = false
  end
end

function Game.mousepressed()
  if Game.state == "playing" and not Game.paused and not Game.seedEntry.active and not Game.conversation.active then
    love.mouse.setRelativeMode(true)
  end
end

function Game.mousemoved(_, _, dx)
  if love.mouse.getRelativeMode() and Game.state == "playing" and not Game.paused and not Game.seedEntry.active and not Game.conversation.active then
    Game.player.angle = Game.player.angle + dx * 0.0024
  end
end

function Game.gamepadpressed(_, button)
  if button == "start" then
    togglePause()
  elseif Game.conversation.active then
    if button == "dpup" or button == "leftshoulder" then
      moveConversationCursor(-1)
    elseif button == "dpdown" or button == "rightshoulder" then
      moveConversationCursor(1)
    elseif button == "a" then
      chooseConversationTopic()
    elseif button == "b" or button == "x" then
      closeConversation()
    end
  elseif Game.paused then
    if button == "dpup" then
      moveSettingsCursor(-1)
    elseif button == "dpdown" then
      moveSettingsCursor(1)
    elseif button == "a" then
      beginBinding()
    elseif button == "b" then
      togglePause()
    end
  elseif Game.state == "playing" then
    if button == "a" then
      useSelectedTool()
    elseif button == "x" then
      openInteraction()
    elseif button == "back" then
      Game.mapGamepadHeld = true
    elseif button == "y" then
      Game.statusGamepadHeld = true
    elseif button == "rightshoulder" then
      cycleTool()
      Game.toolWheel.visible = true
      Game.toolWheel.timer = 1.8
    elseif button == "leftshoulder" then
      for i, tool in ipairs(toolOrder) do
        if tool == Game.inventory.selected then
          selectToolByIndex(((i - 2) % #toolOrder) + 1)
          break
        end
      end
      Game.toolWheel.visible = true
      Game.toolWheel.timer = 1.8
    end
  end
end

function Game.gamepadreleased(_, button)
  if button == "back" then
    Game.mapGamepadHeld = false
  elseif button == "y" then
    Game.statusGamepadHeld = false
  end
end

Game.bindingActions = bindingActions
Game.toolOrder = toolOrder

return Game
