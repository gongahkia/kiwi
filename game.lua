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
  objectives = { total = 0, collected = 0 },
  keys = { total = 0, collected = 0, small = 0, exit = false },
  loopDuration = 60,
  loopTimer = 60,
  respawn = nil,
  mapHeld = false,
  mapGamepadHeld = false,
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
  unlocks = { salvage = 0, unlocked = {}, branches = {} },
  salvage = { carried = 0, total = 0, contamTimer = 0 },
  routeChoices = {},
  routeIndex = 1,
  pendingDeck = nil,
  currentBranch = nil,
  demoMode = false,
  inventory = {
    selected = "flare",
    flare = 1,
    noisemaker = 1,
    bait = 1,
    scent = 1,
    sonic = 0,
    flash = 0,
    snare = 0,
    fuse = 0,
    seal = 0,
    pheromone = 1,
    breaker = 0,
    probe = 1,
    oil = 1,
    valve = 0,
    ground = 0,
    smoke = 0,
    beacon = 0,
    coolant = 0,
    max = { flare = 3, noisemaker = 3, bait = 3, scent = 3, sonic = 2, flash = 2, snare = 2, fuse = 2, seal = 2, pheromone = 2, breaker = 2, probe = 2, oil = 3, valve = 2, ground = 2, smoke = 2, beacon = 2, coolant = 2 },
  },
  message = "",
  messageTimer = 0,
  hazardTimer = 0,
  terminal = { active = false, input = "", current = nil, logs = {}, liftAuthorized = true },
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

local recordCodexDiscovery

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

local unlockThresholds = {
  { salvage = 2, id = "start_probe", text = "Start future runs with an extra survey probe." },
  { salvage = 3, id = "preview_faction", text = "Route choices reveal dominant faction pressure." },
  { salvage = 4, id = "start_pheromone", text = "Start future runs with an extra pheromone vial." },
  { salvage = 5, id = "preview_incident", text = "Route choices reveal likely incident pressure." },
  { salvage = 6, id = "start_breaker", text = "Start future runs with a breaker plug." },
  { salvage = 7, id = "rare_cache", text = "Salvage routes can contain an extra rare cache." },
}

local function saveUnlocks()
  if not love.filesystem then
    return
  end

  local lines = { "salvage=" .. tostring(Game.unlocks.salvage or 0) }
  for id in pairs(Game.unlocks.unlocked or {}) do
    lines[#lines + 1] = "unlock=" .. id
  end
  for biome in pairs(Game.unlocks.branches or {}) do
    lines[#lines + 1] = "branch=" .. biome
  end
  pcall(love.filesystem.write, "unlocks.txt", table.concat(lines, "\n"))
end

local function loadUnlocks()
  Game.unlocks = { salvage = 0, unlocked = {}, branches = {} }
  if not love.filesystem or not love.filesystem.getInfo or not love.filesystem.getInfo("unlocks.txt") then
    return
  end

  local ok, data = pcall(love.filesystem.read, "unlocks.txt")
  if not ok or not data then
    return
  end

  for line in data:gmatch("[^\n]+") do
    local key, value = line:match("^([^=]+)=([^=]+)$")
    if key == "salvage" then
      Game.unlocks.salvage = tonumber(value) or 0
    elseif key == "unlock" then
      Game.unlocks.unlocked[value] = true
    elseif key == "branch" then
      Game.unlocks.branches[value] = true
    end
  end
end

local function updateUnlocks()
  local changed = false
  for _, unlock in ipairs(unlockThresholds) do
    if (Game.unlocks.salvage or 0) >= unlock.salvage and not Game.unlocks.unlocked[unlock.id] then
      Game.unlocks.unlocked[unlock.id] = true
      recordCodexDiscovery("unlock", unlock.id, unlock.text)
      changed = true
    end
  end

  if changed then
    saveUnlocks()
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

local function codexKey(kind, id)
  return (kind or "misc") .. ":" .. (id or "unknown")
end

local function saveCodex()
end

local function loadCodex()
end

function recordCodexDiscovery(kind, id, text)
end

Game.recordCodexDiscovery = recordCodexDiscovery

local function addTerminalLog(text)
  local terminal = Game.terminal.current
  local logs = terminal and terminal.logs or Game.terminal.logs

  logs[#logs + 1] = text
  while #logs > 6 do
    table.remove(logs, 1)
  end
  Game.terminal.logs = logs
end

local function deckSeed(seed, deck)
  return seed + deck * 1000003
end

local creatureCodex = {
  hunter = "Hunters are apex predators that track noise, sight, and weaker prey.",
  stalker = "Stalkers prefer dark territory and retreat from strong light or flash bursts.",
  skitter = "Skitters are scavengers that panic loudly and steal useful objects.",
  screecher = "Screechers are sound predators that can drag other threats toward noise.",
  burrower = "Burrowers guard rubble and flooded nests, but loud bait can pull them off a crossing.",
  warden = "Wardens guard locked routes and react aggressively to breaker sparks, fuse bursts, and cache theft.",
  leecher = "Leechers follow flooded conductors and are repelled by grounding spikes.",
  mimic = "Mimics impersonate useful signals or caches until proximity or survey pulses wake them.",
  choir = "Choirs coordinate through vents and amplify noise pressure during blackouts or blooms.",
  scavenger = "Scavenger rivals steal exposed caches and carried salvage, then flee toward cover.",
}

local districtCodex = {
  collapsed_caves = "Collapsed caves create rubble loops, dark pockets, and burrower routes.",
  flooded_basin = "Flooded basins slow movement and make wire hazards nastier until pumps come online.",
  machine_maze = "Machine mazes carry vents, grates, and sound paths for screechers.",
  foundry_arena = "Foundry arenas are exposed crossings where predators can interrupt each other.",
  salvage_vault = "Cache vaults hold tools, but they often attract rivals and mimics.",
  nest_zone = "Nest zones are creature homes. Raiding or baiting them raises local aggression.",
  cryo_vault = "Cryo vaults carry frost traces, brittle seals, and low-visibility shortcut risks.",
  fungal_service = "Fungal service tunnels amplify scent tools and create misleading spore trails.",
  pressure_lab = "Pressure labs link doors, alarms, glass sight lines, and seal timing.",
  reactor_trench = "Reactor trenches reward overcharge timing but punish heat and sound mistakes.",
  waste_artery = "Waste arteries slow movement, strengthen burrowers in sludge, and contaminate salvage.",
  storm_drain = "Storm drains push flood cycles through live conduit routes; valves and grounding spikes create safe windows.",
  ash_foundry = "Ash foundries hide movement in smoke but turn heat cycles into shelter races.",
  signal_catacombs = "Signal catacombs spoof map pings and hide mimics among cache signs.",
  bone_market = "Bone markets are scavenger trade routes where caches attract rivals and predators.",
  organ_machine = "Organ machines pulse living doors and biological alarms around powered systems.",
}

local startDeck

local incidentDefs = {
  blackout = {
    label = "BLACKOUT",
    signal = "dark_pulse",
    codex = "Blackouts suppress powered light long enough for stalkers to expand territory.",
  },
  flood_surge = {
    label = "FLOOD SURGE",
    signal = "wet_tracks",
    codex = "Flood surges spread water pressure and make wire rooms harder until pumps answer.",
  },
  vent_bloom = {
    label = "VENT BLOOM",
    signal = "vent_call",
    codex = "Vent blooms carry sound through machine districts and wake screechers.",
  },
  heat_spike = {
    label = "HEAT SPIKE",
    signal = "ash_drift",
    codex = "Heat spikes make foundry embers flare until vents or pumps cut the pressure.",
  },
  lockdown = {
    label = "LOCKDOWN",
    signal = "seal_mark",
    codex = "Lockdowns seal routes temporarily, splitting creatures and players into new paths.",
  },
  nest_wake = {
    label = "NEST WAKE",
    signal = "alarm_mark",
    codex = "Nest wake events send guards and raiders toward any fresh territorial disturbance.",
  },
  faction_raid = {
    label = "FACTION RAID",
    signal = "trade_mark",
    codex = "Faction raids pull scavengers and predators toward exposed salvage and alarm marks.",
  },
}

local signalCodex = {
  track = "Tracks show where creatures recently moved. Survey probes reveal older paths.",
  scratch = "Scratch marks usually mean a predator route crosses this room.",
  nest_debris = "Nest debris marks a home territory. Bait and noise nearby can wake guards.",
  wet_tracks = "Wet tracks warn that a flood surge or basin route is active.",
  ash_drift = "Ash drift marks heat pressure and ember risk.",
  vent_call = "Vent calls mean sound will travel farther than normal.",
  alarm_mark = "Alarm marks show a nest has started defending or calling raiders.",
  dark_pulse = "Dark pulses tell you lights are unreliable here.",
  pheromone = "Pheromones create false territory boundaries that can redirect predators.",
  survey_ping = "Survey pings expose recent movement without giving exact creature positions.",
  seal_mark = "Seal marks show a lockdown route that will reopen after pressure drops.",
  frost_trace = "Frost traces mark cryo routes where flares and breakers can reveal brittle shortcuts.",
  spore_bloom = "Spore blooms amplify scent and can make false trails more convincing.",
  pressure_tick = "Pressure ticks warn that doors, glass sight lines, and alarms are coupled.",
  radiant_heat = "Radiant heat marks reactor pressure that vents, pumps, or careful overcharge can manage.",
  tainted_sludge = "Tainted sludge marks waste routes where salvage may decay before extraction.",
  surge_line = "Surge lines show where water pressure will return during the next flood phase.",
  smoke_veil = "Smoke veils break sight but carry noise and can hide stalkers.",
  false_ping = "False pings can mark real caches, mimic bait, or old signs until surveyed.",
  trade_mark = "Trade marks warn that scavenger rivals watch nearby caches.",
  pulse_mark = "Pulse marks show living machinery that reacts to power and coolant.",
  shelter_mark = "Shelter marks identify temporary pockets that reduce cycle pressure.",
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
  for _, terminal in ipairs(Game.level.terminals or {}) do
    local logs = terminal.terminal and terminal.terminal.logs
    if logs then
      logs[#logs + 1] = text
      while #logs > 6 do
        table.remove(logs, 1)
      end
    end
  end
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
  recordCodexDiscovery("incident", kind, def.codex)
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
    local vent = Game.level.terminals[1] or Game.level.exit or { x = Game.player.x, y = Game.player.y }
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
        if signalCodex[signal.kind] then
          recordCodexDiscovery("signal", signal.kind, signalCodex[signal.kind])
        end
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

local function recordDeckDiscoveries()
  for _, district in ipairs(Game.level.districts or {}) do
    if districtCodex[district.kind] then
      recordCodexDiscovery("district", district.kind, districtCodex[district.kind])
    end
  end

  for _, faction in ipairs(Game.level.factions or {}) do
    recordCodexDiscovery("faction", faction.name, "This faction controls territory, alarms nests, and reacts to theft or route manipulation.")
  end

  for _, creature in ipairs(Game.creatures or {}) do
    if creatureCodex[creature.kind] then
      recordCodexDiscovery("creature", creature.kind, creatureCodex[creature.kind])
    end
  end
end

local routeSpecs = {
  safe = { label = "SAFER ROUTE", risk = 1, salvage = 1, description = "Lower pressure, fewer caches, clearer exits." },
  salvage = { label = "RICH SALVAGE", risk = 2, salvage = 3, description = "More caches and rooms, more hazards." },
  conflict = { label = "FACTION CONFLICT", risk = 3, salvage = 2, description = "Two factions contest the route." },
}

local routeOrder = { "safe", "salvage", "conflict" }

local function routeBiome(nextDeck, offset)
  local order = Level.biomeOrder or {}
  local count = #order
  local index = ((Game.seed + nextDeck * 7 + offset * 3) % count) + 1
  return order[index]
end

local function makeRouteChoices(nextDeck)
  local choices = {}

  for i, kind in ipairs(routeOrder) do
    local biome = routeBiome(nextDeck, i)
    local profile = Level.biomeProfiles[biome]
    local spec = routeSpecs[kind]
    local incident = profile.incidents[((Game.seed + nextDeck + i) % #profile.incidents) + 1]
    local faction = kind == "conflict" and profile.factions[min(2, #profile.factions)] or profile.primaryFaction

    choices[#choices + 1] = {
      kind = kind,
      biome = biome,
      biomeLabel = profile.label,
      risk = spec.risk,
      salvage = spec.salvage,
      faction = faction,
      incident = incident,
      label = spec.label,
      description = spec.description,
      previewFaction = Game.unlocks.unlocked.preview_faction or Game.unlocks.branches[biome],
      previewIncident = Game.unlocks.unlocked.preview_incident or Game.unlocks.branches[biome],
      rareCache = Game.unlocks.unlocked.rare_cache and kind == "salvage",
    }
  end

  return choices
end

local function bankSalvage()
  if (Game.salvage.carried or 0) <= 0 then
    return
  end

  Game.unlocks.salvage = (Game.unlocks.salvage or 0) + Game.salvage.carried
  Game.salvage.total = Game.unlocks.salvage
  setMessage("SALVAGE BANKED +" .. Game.salvage.carried, 1.6)
  Game.salvage.carried = 0
  Game.salvage.contamTimer = 0
  updateUnlocks()
  saveUnlocks()
end

local function openRouteSelect(nextDeck)
  Game.pendingDeck = nextDeck
  Game.routeChoices = makeRouteChoices(nextDeck)
  Game.routeIndex = 1
  Game.state = "route_select"
  love.mouse.setRelativeMode(false)
  setMessage("CHOOSE DESCENT ROUTE", 1.7)
end

local function chooseRoute(index)
  local choice = Game.routeChoices[index or Game.routeIndex]
  if not choice then
    return
  end

  Game.currentBranch = choice
  Game.unlocks.branches[choice.biome] = true
  saveUnlocks()
  startDeck(Game.pendingDeck or (Game.deck + 1))
end

function startDeck(deck)
  Game.deck = deck
  love.math.setRandomSeed(deckSeed(Game.seed, deck))

  Game.level = Level.generate(nil, nil, deck, Game.currentBranch)
  Game.player = Actor.createPlayer(Game.level)
  Game.creatures = Actor.createCreatures(Game.level)
  Game.npcs = Actor.createNPCs(Game.level)
  Game.enemy = Actor.nearestThreat(Game) or Game.creatures[1] or Actor.createEnemy(Game.level)
  Game.state = "playing"
  Game.objectives = { total = 0, collected = 0 }
  Game.keys = { total = #Game.level.keys, collected = 0, small = 0, exit = false }
  Game.loopTimer = Game.loopDuration
  Game.respawn = { x = Game.player.x, y = Game.player.y }
  Game.level.visitedMap = {}
  Game.terminal = {
    active = false,
    input = "",
    current = nil,
    logs = {},
    liftAuthorized = not Game.level.liftRequired,
  }
  Game.conversation = { active = false, npc = nil, topics = {}, index = 1, response = "" }
  Game.noise = { ttl = 0, intensity = 0, radius = 0, x = 0, y = 0 }
  Game.noises = {}
  Game.effects = {}
  Game.props = {}
  Game.survey = { ttl = 0 }
  Game.toolWheel = { visible = false, timer = 0 }
  Game.mapHeld = false
  Game.mapGamepadHeld = false
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
    bait = 1,
    scent = 1,
    sonic = 0,
    flash = 0,
    snare = 0,
    fuse = 0,
    seal = 0,
    pheromone = 1,
    breaker = 0,
    probe = 1,
    oil = 1,
    valve = 0,
    ground = 0,
    smoke = 0,
    beacon = 0,
    coolant = 0,
    max = { flare = 3, noisemaker = 3, bait = 3, scent = 3, sonic = 2, flash = 2, snare = 2, fuse = 2, seal = 2, pheromone = 2, breaker = 2, probe = 2, oil = 3, valve = 2, ground = 2, smoke = 2, beacon = 2, coolant = 2 },
  }
  if Game.unlocks.unlocked.start_probe then
    Game.inventory.probe = min(Game.inventory.max.probe, Game.inventory.probe + 1)
  end
  if Game.unlocks.unlocked.start_pheromone then
    Game.inventory.pheromone = min(Game.inventory.max.pheromone, Game.inventory.pheromone + 1)
  end
  if Game.unlocks.unlocked.start_breaker then
    Game.inventory.breaker = min(Game.inventory.max.breaker, Game.inventory.breaker + 1)
  end
  Game.salvage = { carried = 0, total = 0, contamTimer = 0 }
  Game.currentBranch = nil
  Game.routeChoices = {}
  Game.routeIndex = 1
  Game.pendingDeck = nil
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

  Game.currentBranch = nil
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
  Game.terminal.active = false
  Game.loopTimer = Game.loopDuration
  Game.torch.fuel = 1
  Game.inventory.flare = 1
  Game.inventory.noisemaker = 1
  Game.inventory.bait = 1
  Game.inventory.scent = 1
  Game.inventory.pheromone = 1
  Game.inventory.probe = 1
  Game.inventory.oil = 1
  Game.inventory.sonic = 0
  Game.inventory.flash = 0
  Game.inventory.snare = 0
  Game.inventory.fuse = 0
  Game.inventory.seal = 0
  Game.inventory.breaker = 0
  Game.inventory.valve = 0
  Game.inventory.ground = 0
  Game.inventory.smoke = 0
  Game.inventory.beacon = 0
  Game.inventory.coolant = 0
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

    if effect.kind == "noisemaker" and effect.pulse <= 0 then
      Actor.emitNoise(Game, effect.x, effect.y, 3.2, 1.1, "noisemaker")
      effect.pulse = 1.15
    elseif effect.kind == "flare" and effect.pulse <= 0 then
      Actor.emitNoise(Game, effect.x, effect.y, 1.5, 0.8, "flare")
      effect.pulse = 1.4
    elseif effect.kind == "seal" and effect.gate and effect.ttl <= 0 then
      effect.gate.cell.gateLocked = false
    elseif effect.kind == "lockdown" and effect.gate and effect.ttl <= 0 then
      effect.gate.cell.gateLocked = effect.previousLocked or false
    elseif effect.kind == "thaw_gate" and effect.gate and effect.ttl <= 0 then
      effect.gate.cell.gateLocked = effect.previousLocked or false
    elseif effect.kind == "breaker_door" and effect.gate and effect.ttl <= 0 then
      effect.gate.cell.gateLocked = effect.previousLocked or false
      if effect.gate.cell.lock then
        effect.gate.cell.lock.locked = effect.previousLocked or false
      end
    elseif effect.kind == "breaker" and effect.system and effect.ttl <= 0 then
      if effect.restore then
        Level.setSystemPowered(Game.level, effect.system, true)
      end
    elseif effect.kind == "hazard_suppress" and effect.hazard and effect.ttl <= 0 then
      if effect.hazard.cell and effect.hazard.cell.hazard then
        effect.hazard.cell.hazard.suppressed = false
      end
      Level.applySystemEffects(Game.level)
    end

    if effect.ttl <= 0 then
      if effect.kind == "fuse" then
        Game.level.power.temporary = max(0, (Game.level.power.temporary or 0) - (effect.amount or 1))
        Level.applySystemEffects(Game.level)
        setMessage("FUSE EXPIRED", 1.2)
      end
      table.remove(Game.effects, i)
    end
  end

  local decoy = Game.level.systems and Game.level.systems.decoy
  if decoy and decoy.powered then
    decoy.cooldown = max(0, (decoy.cooldown or 0) - dt)
    if decoy.cooldown <= 0 then
      local terminal = Game.level.terminals[#Game.level.terminals] or Game.level.exit or { x = Game.player.x, y = Game.player.y }
      Actor.emitNoise(Game, terminal.x + 0.5, terminal.y + 0.5, 3.4, 1.2, "decoy")
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
      if prop.kind == "sonic" then
        Actor.emitNoise(Game, prop.x, prop.y, 4.0, 1.3, "sonic")
        prop.pulse = 1.05
      elseif prop.kind == "scent" then
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
      elseif prop.kind == "smoke" then
        addSignal("smoke_veil", prop.x, prop.y, 1.2, 7, "player", true)
        Actor.emitNoise(Game, prop.x, prop.y, 1.4, 1.0, "smoke")
        prop.pulse = 3.0
      elseif prop.kind == "beacon" then
        addSignal("trade_mark", prop.x, prop.y, 1.4, 9, "player", true)
        Actor.emitNoise(Game, prop.x, prop.y, 3.8, 1.2, "beacon")
        prop.pulse = 1.8
      elseif prop.kind == "fuse" then
        Actor.emitNoise(Game, prop.x, prop.y, 3.6, 1.0, "fuse")
        prop.pulse = 1.2
      elseif prop.kind == "ground" then
        addSignal("surge_line", prop.x, prop.y, 0.8, 6, "player", true)
        prop.pulse = 4.0
      elseif prop.kind == "coolant" then
        addSignal("smoke_veil", prop.x, prop.y, 0.9, 6, "coolant", true)
        prop.pulse = 3.6
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
  for _, effect in ipairs(Game.effects or {}) do
    local dx = (effect.x or 0) - Game.player.x
    local dy = (effect.y or 0) - Game.player.y
    if effect.kind == "ground" and cell.hazard.kind == "wire" and dx * dx + dy * dy < 16 then
      drain = drain - 0.04
    elseif effect.kind == "coolant" and cell.hazard.kind == "ember" and dx * dx + dy * dy < 16 then
      drain = drain - 0.05
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

local function updateSalvage(dt)
  if (Game.salvage.contamTimer or 0) <= 0 then
    return
  end

  Game.salvage.contamTimer = max(0, Game.salvage.contamTimer - dt)
  if Game.salvage.contamTimer <= 0 and (Game.salvage.carried or 0) > 0 then
    Game.salvage.carried = max(0, Game.salvage.carried - 1)
    setMessage("CONTAMINATED SALVAGE SPOILED", 1.6)
  end
end

local function terminalAtPlayer()
  local px = floor(Game.player.x)
  local py = floor(Game.player.y)

  for _, terminal in ipairs(Game.level.terminals or {}) do
    if abs(terminal.x - px) + abs(terminal.y - py) <= 1 then
      return terminal
    end
  end

  return nil
end

function Game.nearTerminal()
  if not Game.level or not Game.player then
    return nil
  end

  return terminalAtPlayer()
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

local function terminalTopic()
  local level = Game.level
  local terminal = nearestItem(level.terminals, function(item)
    if level.liftRequired and not level.liftAuthorized then
      return item.command == "LIFT"
    end
    return true
  end)

  if not terminal then
    return { id = "terminal", label = "Terminal", response = "No terminal is readable from here. Keep the map open after a SCAN." }
  end

  local command = terminal.command or "SCAN"
  local advice = NPCContent.commandAdvice[command] or "Terminals reroute deck systems."
  local power = string.format("Power is %d/%d assigned.", level.power.assigned or 0, Level.powerCapacity(level))
  local liftHint = ""
  if command == "LIFT" and Game.objectives.collected < (level.minLiftRelays or Game.objectives.total) then
    liftHint = " You still need more relays before it will answer."
  end

  return {
    id = "terminal",
    label = "Terminal",
    response = string.format("Nearest terminal is %s. %s %s%s", directionToCell(terminal.x, terminal.y), advice, power, liftHint),
    target = topicTarget(terminal),
    lead = true,
  }
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

local function salvageTopic()
  local cache = nearestItem(Game.level.toolCaches, function(item)
    return item.cell and item.cell.tool and not item.cell.toolUsed
  end)
  local response

  if Game.level.salvageLocked then
    response = "Lift routing has sealed optional salvage. Stop chasing caches and leave clean."
  else
    response = string.format("You are carrying %d salvage. Banked total is %d.", Game.salvage.carried or 0, Game.unlocks.salvage or 0)
    if cache then
      local warning = cache.cell.tool and cache.cell.tool.mimic and " It reads wrong; probe it before touching." or ""
      response = response .. " Nearest cache is " .. directionToCell(cache.x, cache.y) .. "." .. warning
    end
  end

  return {
    id = "salvage",
    label = "Salvage",
    response = response,
    target = cache and topicTarget(cache) or nil,
    lead = cache ~= nil and not Game.level.salvageLocked,
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

local function openTerminal()
  local terminal = terminalAtPlayer()
  if not terminal then
    setMessage("NO TERMINAL", 0.8)
    return
  end

  Game.terminal.active = true
  Game.terminal.input = ""
  Game.terminal.current = terminal.terminal
  Game.terminal.logs = terminal.terminal.logs
  addTerminalLog("SESSION OPEN")
  love.mouse.setRelativeMode(false)
end

local function openInteraction()
  if Game.terminal.active or Game.conversation.active then
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

local function closeTerminal()
  Game.terminal.active = false
  Game.terminal.input = ""
  Game.terminal.current = nil
  Game.terminal.logs = {}
  if Game.state == "playing" then
    love.mouse.setRelativeMode(true)
  end
end

local function terminalNoise()
  local terminal = terminalAtPlayer()
  local x = terminal and terminal.x + 0.5 or Game.player.x
  local y = terminal and terminal.y + 0.5 or Game.player.y

  Actor.emitNoise(Game, x, y, 2.2, 0.9, "terminal")
end

local systemAliases = {
  ["1"] = "lights",
  LIGHT = "lights",
  LIGHTS = "lights",
  ["2"] = "doors",
  DOOR = "doors",
  DOORS = "doors",
  ["3"] = "pumps",
  PUMP = "pumps",
  PUMPS = "pumps",
  ["4"] = "vents",
  VENT = "vents",
  VENTS = "vents",
  ["5"] = "decoy",
  DECOY = "decoy",
  ["6"] = "lift",
  LIFT = "lift",
}

local toolOrder = { "flare", "noisemaker", "bait", "scent", "sonic", "flash", "snare", "fuse", "seal", "pheromone", "breaker", "probe", "oil", "valve", "ground", "smoke", "beacon", "coolant" }

local function addInventory(kind, amount)
  local maxCount = Game.inventory.max[kind] or 0
  if maxCount <= 0 then
    return false
  end

  local before = Game.inventory[kind] or 0
  Game.inventory[kind] = U.clamp(before + (amount or 1), 0, maxCount)
  return Game.inventory[kind] > before
end

local function routeSystem(name)
  if name == "lift" and Game.objectives.collected < (Game.level.minLiftRelays or Game.objectives.total) then
    addTerminalLog("MIN RELAYS REQUIRED")
    terminalNoise()
    return
  end

  local ok, message = Level.toggleSystem(Game.level, name)
  if ok and name == "lift" and Game.level.systems.lift.powered and Game.objectives.collected < Game.objectives.total then
    Game.level.salvageLocked = true
    message = message .. " SALVAGE SEALED"
  end
  addTerminalLog(message)
  terminalNoise()
  if ok then
    Audio.relay()
  end
end

local function executeTerminalCommand()
  local terminal = Game.terminal.current
  local command = Game.terminal.input

  Game.terminal.input = ""
  if not terminal or command == "" then
    return
  end

  addTerminalLog("> " .. command)
  local systemName = systemAliases[command]
  if systemName then
    routeSystem(systemName)
    return
  end

  if command ~= terminal.command then
    addTerminalLog("COMMAND REJECTED")
    terminalNoise()
    return
  end

  if command == "SCAN" then
    if Game.level.scanRevealed then
      addTerminalLog("SCAN CACHE READY")
    else
      Game.level.scanRevealed = true
      Game.showMap = true
      terminal.used = true
      addTerminalLog("MAP NODES REVEALED")
      Audio.relay()
    end
  elseif command == "UNLOCK" then
    local ok, message = Level.unlockTerminalTarget(Game.level, terminal)
    addTerminalLog(message)
    if ok then
      Audio.relay()
    else
      terminalNoise()
    end
  elseif command == "PURGE" then
    local ok, message = Level.purgeTerminalHazards(Game.level, terminal)
    addTerminalLog(message)
    if ok then
      Audio.relay()
    else
      terminalNoise()
    end
  elseif command == "LIFT" then
    if Game.objectives.collected < Game.objectives.total and Game.objectives.collected < (Game.level.minLiftRelays or Game.objectives.total) then
      addTerminalLog("RELAYS OFFLINE")
      terminalNoise()
    else
      Level.setSystemPowered(Game.level, "lift", true)
      Game.terminal.liftAuthorized = true
      terminal.used = true
      addTerminalLog("LIFT AUTHORIZED")
      Audio.relay()
    end
  end
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

local function nearestGate(maxDistance)
  local best
  local bestDistance = maxDistance or 2.3

  for _, gate in ipairs(Game.level.gates or {}) do
    local dx = gate.x + 0.5 - Game.player.x
    local dy = gate.y + 0.5 - Game.player.y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < bestDistance then
      best = gate
      bestDistance = distance
    end
  end

  return best
end

local function breakerSystem()
  local cell = Level.cellAtWorld(Game.level, Game.player.x, Game.player.y) or {}
  local systems = Game.level.systems or {}

  if cell.hazard and cell.hazard.kind == "wire" and systems.pumps and systems.pumps.powered then
    return "pumps"
  elseif cell.vent and systems.vents and systems.vents.powered then
    return "vents"
  elseif nearestGate(2.8) and systems.doors and systems.doors.powered then
    return "doors"
  elseif systems.lights and systems.lights.powered then
    return "lights"
  elseif systems.decoy and systems.decoy.powered then
    return "decoy"
  elseif systems.vents and systems.vents.powered then
    return "vents"
  elseif systems.pumps and systems.pumps.powered then
    return "pumps"
  end

  return nil
end

local function suppressHazardsNear(x, y, kinds, radius, ttl, effectKind)
  local suppressed = 0
  local radiusSq = (radius or 3.6) * (radius or 3.6)
  for _, hazard in ipairs(Game.level.hazards or {}) do
    local active = hazard.cell and hazard.cell.hazard and hazard.cell.hazard.active
    if active and kinds[hazard.cell.hazard.kind] then
      local dx = hazard.x + 0.5 - x
      local dy = hazard.y + 0.5 - y
      if dx * dx + dy * dy <= radiusSq then
        hazard.cell.hazard.suppressed = true
        hazard.cell.light = min(hazard.cell.light or 0.5, 0.42)
        Game.effects[#Game.effects + 1] = { kind = "hazard_suppress", x = hazard.x + 0.5, y = hazard.y + 0.5, ttl = ttl or 16, hazard = hazard, source = effectKind }
        suppressed = suppressed + 1
      end
    end
  end
  return suppressed
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

  local x, y = dropPoint(tool == "seal" and 1.0 or 1.8)
  Game.inventory[tool] = Game.inventory[tool] - 1

  if tool == "flare" then
    Game.effects[#Game.effects + 1] = { kind = "flare", x = x, y = y, ttl = 9, radius = 8.5, pulse = 0 }
    Game.props[#Game.props + 1] = { kind = "flare", x = x, y = y, ttl = 9, pulse = 0 }
    Actor.emitNoise(Game, x, y, 1.8, 1.2, "flare")
    if biome == "cryo_vault" then
      addSignal("frost_trace", x, y, 1.6, 18, "flare", true)
      Game.survey.ttl = max(Game.survey.ttl or 0, 5)
    end
    recordCodexDiscovery("tool", "flare", "Flares reveal nearby ground and repel stalkers, but they still draw sight and sound predators.")
    setMessage("FLARE BURNING", 1.2)
  elseif tool == "noisemaker" then
    Game.props[#Game.props + 1] = { kind = "noisemaker", x = x, y = y, ttl = 8, pulse = 0 }
    recordCodexDiscovery("tool", "noisemaker", "Noisemakers pull screechers and hunters toward repeated pulses.")
    setMessage("NOISEMAKER ARMED", 1.2)
  elseif tool == "bait" then
    Game.props[#Game.props + 1] = { kind = "bait", x = x, y = y, ttl = 22, scent = "meat" }
    recordCodexDiscovery("tool", "bait", "Bait can feed or redirect predators, but bait near a nest may trigger guarding.")
    setMessage("BAIT DEPLOYED", 1.2)
  elseif tool == "scent" then
    Game.props[#Game.props + 1] = { kind = "scent", x = x, y = y, ttl = 28, pulse = 0, scent = "player" }
    if biome == "fungal_service" then
      addSignal("spore_bloom", x, y, 1.5, 24, "player", true)
      Actor.emitNoise(Game, Game.player.x, Game.player.y, 2.6, 1.3, "spore")
      recordCodexDiscovery("biome", "fungal_scent", "In fungal service tunnels scent markers can create convincing false trails, but spores also echo your presence.")
    end
    recordCodexDiscovery("tool", "scent", "Scent markers create a false trail for hunters and stalkers.")
    setMessage("SCENT MARKER", 1.2)
  elseif tool == "sonic" then
    Game.props[#Game.props + 1] = { kind = "sonic", x = x, y = y, ttl = 12, pulse = 0 }
    recordCodexDiscovery("tool", "sonic", "Sonic stakes pulse loudly enough to pull screechers into other creatures.")
    setMessage("SONIC STAKE", 1.2)
  elseif tool == "flash" then
    Game.props[#Game.props + 1] = { kind = "flash", x = x, y = y, ttl = 6, armed = true }
    Game.effects[#Game.effects + 1] = { kind = "flash", x = x, y = y, ttl = 6, radius = 5.5 }
    setMessage("FLASH POD SET", 1.2)
  elseif tool == "snare" then
    Game.props[#Game.props + 1] = { kind = "snare", x = x, y = y, ttl = 30, armed = true }
    setMessage("SNARE WIRE", 1.2)
  elseif tool == "fuse" then
    Game.props[#Game.props + 1] = { kind = "fuse", x = x, y = y, ttl = 10, pulse = 0 }
    Actor.emitNoise(Game, x, y, 4.2, 1.4, "fuse")
    if biome == "reactor_trench" then
      addSignal("radiant_heat", x, y, 1.5, 18, "fuse", true)
    end
    setMessage("FUSE SPARK", 1.2)
  elseif tool == "seal" then
    local gate = nearestGate()
    if gate then
      gate.cell.gateLocked = true
      Game.effects[#Game.effects + 1] = { kind = "seal", x = gate.x + 0.5, y = gate.y + 0.5, ttl = 15, gate = gate }
      if biome == "pressure_lab" then
        addSignal("pressure_tick", gate.x + 0.5, gate.y + 0.5, 1.5, 18, "seal", true)
        Actor.emitNoise(Game, gate.x + 0.5, gate.y + 0.5, 2.7, 1.1, "alarm")
        alarmFaction(gate.cell.faction, 6, gate.x + 0.5, gate.y + 0.5, "seal")
      end
      setMessage("SEAL CHARGE SET", 1.2)
    else
      addInventory("seal", 1)
      setMessage("NO GATE NEARBY", 0.9)
    end
  elseif tool == "pheromone" then
    local ttl = biome == "fungal_service" and 48 or 34
    local strength = biome == "fungal_service" and 1.9 or 1.4
    Game.props[#Game.props + 1] = { kind = "pheromone", x = x, y = y, ttl = ttl, pulse = 0, scent = "territory" }
    addSignal("pheromone", x, y, strength, ttl, "player", true)
    local cell = Level.cellAtWorld(Game.level, x, y) or {}
    alarmFaction(cell.faction, biome == "fungal_service" and 7 or 4, x, y, "pheromone")
    recordCodexDiscovery("tool", "pheromone", "Pheromone vials draw a false territory edge that predators hesitate to cross.")
    setMessage("PHEROMONE BOUNDARY", 1.2)
  elseif tool == "breaker" then
    local door = nearbyLockedDoor()
    if door then
      local previousLocked = door.cell.gateLocked or (door.cell.lock and door.cell.lock.locked)
      door.cell.gateLocked = false
      if door.cell.lock then
        door.cell.lock.locked = false
      end
      Game.effects[#Game.effects + 1] = { kind = "breaker_door", x = door.x + 0.5, y = door.y + 0.5, ttl = 16, gate = door, previousLocked = previousLocked }
      addSignal("seal_mark", door.x + 0.5, door.y + 0.5, 1.1, 16, "breaker", true)
      setMessage("BREAKER OPEN", 1.2)
    else
      addInventory("breaker", 1)
      setMessage("NO LOCK NEARBY", 0.9)
    end
  elseif tool == "probe" then
    Game.survey.ttl = 12
    Game.props[#Game.props + 1] = { kind = "probe", x = x, y = y, ttl = 12, pulse = 0 }
    addSignal("survey_ping", x, y, 1.2, 12, "player", true)
    recordCodexDiscovery("tool", "probe", "Survey probes reveal recent ecology signs without showing exact creature positions.")
    setMessage("SURVEY PULSE", 1.2)
  elseif tool == "valve" then
    Game.props[#Game.props + 1] = { kind = "valve", x = x, y = y, ttl = 14, pulse = 0 }
    local suppressed = suppressHazardsNear(x, y, { wire = true }, 4.2, 14, "valve")
    if Game.ecology then
      Game.ecology.flood = max(0, (Game.ecology.flood or 0) - 6)
    end
    addSignal("surge_line", x, y, 1.5, 18, "valve", true)
    Actor.emitNoise(Game, x, y, 2.6, 1.1, "valve")
    recordCodexDiscovery("tool", "valve", "Valve cranks redirect flood pressure, briefly calming live water and wire routes.")
    setMessage("VALVE TURNED " .. suppressed .. " LINES", 1.3)
  elseif tool == "ground" then
    Game.props[#Game.props + 1] = { kind = "ground", x = x, y = y, ttl = 18, pulse = 0 }
    Game.effects[#Game.effects + 1] = { kind = "ground", x = x, y = y, ttl = 18, radius = 4.2 }
    local suppressed = suppressHazardsNear(x, y, { wire = true }, 4.2, 18, "ground")
    addSignal("surge_line", x, y, 1.1, 18, "ground", true)
    recordCodexDiscovery("tool", "ground", "Grounding spikes make nearby powered water safe enough to cross and repel leechers.")
    setMessage("GROUND SPIKE " .. suppressed .. " WIRES", 1.3)
  elseif tool == "smoke" then
    Game.props[#Game.props + 1] = { kind = "smoke", x = x, y = y, ttl = 16, pulse = 0 }
    Game.effects[#Game.effects + 1] = { kind = "smoke", x = x, y = y, ttl = 16, radius = 6.5 }
    addSignal("smoke_veil", x, y, 1.4, 16, "player", true)
    Actor.emitNoise(Game, x, y, 1.9, 1.1, "smoke")
    recordCodexDiscovery("tool", "smoke", "Smoke charges break sight lines, but their turbulent vents can carry noise.")
    setMessage("SMOKE CHARGE", 1.2)
  elseif tool == "beacon" then
    Game.props[#Game.props + 1] = { kind = "beacon", x = x, y = y, ttl = 18, pulse = 0 }
    addSignal("trade_mark", x, y, 1.7, 20, "player", true)
    Actor.emitNoise(Game, x, y, 3.8, 1.4, "beacon")
    local cell = Level.cellAtWorld(Game.level, x, y) or {}
    local fallbackFaction = Game.level.factions and Game.level.factions[1] and Game.level.factions[1].name
    alarmFaction(cell.faction or fallbackFaction, 7, x, y, "beacon")
    recordCodexDiscovery("tool", "beacon", "Lure beacons create a loud salvage mark that pulls scavengers and sound predators away from you.")
    setMessage("LURE BEACON", 1.2)
  elseif tool == "coolant" then
    Game.props[#Game.props + 1] = { kind = "coolant", x = x, y = y, ttl = 14, pulse = 0 }
    Game.effects[#Game.effects + 1] = { kind = "coolant", x = x, y = y, ttl = 14, radius = 4.6 }
    local suppressed = suppressHazardsNear(x, y, { ember = true }, 4.6, 14, "coolant")
    if Game.ecology then
      Game.ecology.heat = max(0, (Game.ecology.heat or 0) - 6)
    end
    if biome == "organ_machine" then
      addSignal("pulse_mark", x, y, 1.4, 18, "coolant", true)
    else
      addSignal("smoke_veil", x, y, 1.2, 14, "coolant", true)
    end
    recordCodexDiscovery("tool", "coolant", "Coolant ampoules quench ember lanes and slow wardens or mimics caught in the burst.")
    setMessage("COOLANT " .. suppressed .. " EMBERS", 1.3)
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

local function moveRouteCursor(delta)
  Game.routeIndex = U.clamp((Game.routeIndex or 1) + delta, 1, max(1, #(Game.routeChoices or {})))
end

function Game.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  Game.fonts.hud = love.graphics.newFont(17)
  Game.fonts.title = love.graphics.newFont(58)
  Renderer.init()
  Audio.init()
  loadSettings()
  loadAchievements()
  loadUnlocks()
  loadCodex()
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
    updateSalvage(dt)
    if not Game.conversation.active then
      checkInteractions()
    end
    Actor.updateCreatures(Game, dt, Audio)
  end
end

function Game.draw()
  Renderer.draw(Game)
  UI.draw(Game)
end

function Game.keypressed(key)
  if Game.bindTarget then
    Game.bindings[Game.bindTarget] = key
    Game.bindTarget = nil
    saveSettings()
    setMessage("CONTROL SAVED", 1)
    return
  end

  if Game.state == "route_select" then
    if key:match("^[1-3]$") then
      chooseRoute(tonumber(key))
    elseif key == "up" or key == "left" then
      moveRouteCursor(-1)
    elseif key == "down" or key == "right" or key == "tab" then
      moveRouteCursor(1)
    elseif key == "return" or key == "kpenter" or key == "space" then
      chooseRoute(Game.routeIndex)
    elseif key == "r" then
      startGame(Game.lastSeed)
    elseif key == "n" then
      startGame()
    end
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
  elseif Game.state == "playing" and key:match("^[1-9]$") then
    selectToolByIndex(tonumber(key))
  elseif Game.state == "playing" and key == "0" then
    selectToolByIndex(10)
  elseif Game.state == "playing" and key == "-" then
    selectToolByIndex(11)
  elseif Game.state == "playing" and key == "=" then
    selectToolByIndex(12)
  elseif Game.state == "playing" and key == "backspace" then
    selectToolByIndex(13)
  elseif key == "x" then
    Renderer.togglePost()
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
  elseif Game.state == "route_select" then
    if button == "dpup" or button == "leftshoulder" then
      moveRouteCursor(-1)
    elseif button == "dpdown" or button == "rightshoulder" then
      moveRouteCursor(1)
    elseif button == "a" then
      chooseRoute(Game.routeIndex)
    elseif button == "b" then
      startGame(Game.lastSeed)
    end
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
  end
end

Game.bindingActions = bindingActions
Game.toolOrder = toolOrder

return Game
