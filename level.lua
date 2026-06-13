local Biomes = require("content.biomes")
local CreatureContent = require("content.creatures")
local NPCContent = require("content.npcs")
local U = require("utils")

local floor = math.floor
local abs = math.abs
local min = math.min
local max = math.max
local sqrt = math.sqrt

local Level = {
  width = 57,
  height = 57,
  maxDecks = 3,
  maxStepHeight = 0.58,
  floorHeight = 0,
  ceilingHeight = 3.05,
}

Level.deckConfigs = {
  { width = 57, height = 57, rooms = 14, keys = 2, refills = 6, gates = 2, locks = 1, hazards = 8 },
  { width = 65, height = 65, rooms = 18, keys = 3, refills = 7, gates = 3, locks = 1, hazards = 12 },
  { width = 73, height = 73, rooms = 22, keys = 3, refills = 8, gates = 3, locks = 2, hazards = 16 },
}

Level.biomeOrder = Biomes.order
Level.biomeProfiles = Biomes.profiles
Level.roomModifiers = Biomes.roomModifiers
Level.roomModifierOrder = Biomes.modifierOrder

local zoneStyles = {
  ["atrium"] = { terrain = "flagstone", light = 0.78 },
  ["archive"] = { terrain = "dust", light = 0.56 },
  ["observatory"] = { terrain = "glass", light = 0.72 },
  ["cistern"] = { terrain = "water", light = 0.52 },
  ["lower foundry"] = { terrain = "grate", light = 0.64 },
  ["overgrown court"] = { terrain = "moss", light = 0.68 },
  ["quarry"] = { terrain = "rubble", light = 0.58 },
  ["machine shaft"] = { terrain = "grate", light = 0.62 },
  ["bridgeworks"] = { terrain = "catwalk", light = 0.64 },
  ["annex"] = { terrain = "stone", light = 0.58 },
  ["chamber"] = { terrain = "stone", light = 0.56 },
  ["hall"] = { terrain = "stone", light = 0.5 },
  ["ladder"] = { terrain = "ladder", light = 0.72 },
}

Level.terrainSpeed = {
  flagstone = 1,
  stone = 1,
  steps = 1,
  dust = 0.95,
  grate = 0.9,
  catwalk = 0.9,
  glass = 0.94,
  moss = 0.84,
  rubble = 0.76,
  water = 0.72,
  slag = 0.78,
  ice = 0.82,
  fungus = 0.8,
  pressure = 0.93,
  reactor = 0.86,
  sludge = 0.64,
  storm = 0.68,
  ash = 0.74,
  signal = 0.94,
  bone = 0.88,
  organ = 0.76,
  ladder = 0.9,
}

Level.terrainLabels = {
  flagstone = "FLAGSTONE",
  stone = "STONE",
  steps = "STONE",
  dust = "DUST",
  grate = "GRATE",
  catwalk = "CATWALK",
  glass = "GLASS",
  moss = "MOSS",
  rubble = "RUBBLE",
  water = "WATER",
  slag = "SLAG",
  ice = "ICE",
  fungus = "FUNGUS",
  pressure = "PRESSURE",
  reactor = "REACTOR",
  sludge = "SLUDGE",
  storm = "STORM",
  ash = "ASH",
  signal = "SIGNAL",
  bone = "BONE",
  organ = "ORGAN",
  ladder = "LADDER",
}

local terminalCommands = { "SCAN", "UNLOCK", "PURGE", "LIFT" }
local systemOrder = { "lights", "doors", "pumps", "vents", "decoy", "lift" }

local directions = {
  { name = "north", dx = 0, dy = -1, opposite = "south" },
  { name = "east", dx = 1, dy = 0, opposite = "west" },
  { name = "south", dx = 0, dy = 1, opposite = "north" },
  { name = "west", dx = -1, dy = 0, opposite = "east" },
}

local directionByName = {}
for _, direction in ipairs(directions) do
  directionByName[direction.name] = direction
end

local moduleTemplates = {
  { id = "atrium", kind = "atrium", width = { 12, 15 }, height = { 10, 13 }, connectors = { north = true, east = true, south = true, west = true } },
  { id = "archive_cross", kind = "archive", width = { 9, 13 }, height = { 8, 11 }, connectors = { north = true, east = true, south = true, west = true } },
  { id = "archive_gallery", kind = "archive", width = { 14, 18 }, height = { 5, 8 }, connectors = { east = true, west = true, south = true } },
  { id = "cistern_run", kind = "cistern", width = { 8, 12 }, height = { 10, 14 }, connectors = { north = true, south = true, east = true } },
  { id = "cistern_pool", kind = "cistern", width = { 12, 16 }, height = { 12, 16 }, connectors = { north = true, east = true, south = true, west = true } },
  { id = "foundry_bend", kind = "lower foundry", width = { 9, 12 }, height = { 8, 11 }, connectors = { north = true, east = true, west = true } },
  { id = "foundry_line", kind = "lower foundry", width = { 6, 9 }, height = { 14, 18 }, connectors = { north = true, south = true, west = true } },
  { id = "overgrown_bend", kind = "overgrown court", width = { 8, 11 }, height = { 8, 12 }, connectors = { east = true, south = true, west = true } },
  { id = "overgrown_garden", kind = "overgrown court", width = { 13, 17 }, height = { 10, 14 }, connectors = { north = true, east = true, south = true, west = true } },
  { id = "quarry_hub", kind = "quarry", width = { 9, 13 }, height = { 8, 12 }, connectors = { north = true, east = true, south = true, west = true } },
  { id = "quarry_pit", kind = "quarry", width = { 13, 17 }, height = { 7, 11 }, connectors = { north = true, south = true, west = true } },
  { id = "machine_spine", kind = "machine shaft", width = { 8, 10 }, height = { 11, 15 }, connectors = { north = true, south = true, west = true } },
  { id = "machine_cross", kind = "machine shaft", width = { 12, 16 }, height = { 9, 12 }, connectors = { north = true, east = true, south = true, west = true } },
  { id = "bridge_bar", kind = "bridgeworks", width = { 11, 15 }, height = { 6, 9 }, connectors = { east = true, west = true, south = true } },
  { id = "bridge_long", kind = "bridgeworks", width = { 16, 22 }, height = { 4, 6 }, connectors = { east = true, west = true } },
  { id = "observatory", kind = "observatory", width = { 10, 14 }, height = { 9, 12 }, connectors = { north = true, east = true, south = true, west = true } },
  { id = "observatory_dome", kind = "observatory", width = { 14, 18 }, height = { 14, 18 }, connectors = { north = true, east = true, south = true, west = true } },
  { id = "annex", kind = "annex", width = { 6, 9 }, height = { 6, 9 }, connectors = { north = true, east = true, south = true, west = true } },
  { id = "annex_deadend", kind = "annex", width = { 5, 8 }, height = { 5, 8 }, connectors = { north = true } },
  { id = "chamber", kind = "chamber", width = { 7, 10 }, height = { 7, 10 }, connectors = { north = true, east = true, south = true, west = true } },
  { id = "chamber_long", kind = "chamber", width = { 5, 8 }, height = { 13, 18 }, connectors = { north = true, south = true, east = true } },
}

local layoutProfiles = {
  { name = "spine", routeRatio = 0.62, gap = { 5, 9 }, jitter = 4, directChance = 0.18, doglegChance = 0.62, sideRouteBias = 0.7, alcoves = 1, openLinks = 0 },
  { name = "cluster", routeRatio = 0.42, gap = { 3, 6 }, jitter = 8, directChance = 0.52, doglegChance = 0.24, sideRouteBias = 0.34, alcoves = 3, openLinks = 2 },
  { name = "sprawl", routeRatio = 0.52, gap = { 7, 11 }, jitter = 7, directChance = 0.22, doglegChance = 0.48, sideRouteBias = 0.5, alcoves = 2, openLinks = 1 },
  { name = "crosslink", routeRatio = 0.48, gap = { 4, 8 }, jitter = 6, directChance = 0.34, doglegChance = 0.4, sideRouteBias = 0.25, alcoves = 2, openLinks = 4 },
}

local metricNeighbors = {
  { 1, 0 },
  { 0, 1 },
}

local function zoneStyle(kind)
  return zoneStyles[kind] or zoneStyles.chamber
end

local function normalizeBranch(branch, deck)
  local order = Level.biomeOrder
  local biome = branch and branch.biome
  if not Level.biomeProfiles[biome] then
    biome = order[((deck or 1) - 1) % #order + 1]
  end

  return {
    kind = branch and branch.kind or "safe",
    biome = biome,
    risk = branch and branch.risk or 1,
    salvage = branch and branch.salvage or 1,
    faction = branch and branch.faction or Level.biomeProfiles[biome].primaryFaction,
    incident = branch and branch.incident or Level.biomeProfiles[biome].incidents[1],
    rareCache = branch and branch.rareCache or false,
  }
end

local function randomRange(range)
  return love.math.random(range[1], range[2])
end

local function makeWallCell()
  return {
    solid = true,
    floor = Level.floorHeight,
    ceiling = Level.ceilingHeight,
    kind = "wall",
    light = 0.3,
    stair = false,
    ladder = false,
    terrain = "stone",
    zone = "outer",
    gate = false,
    gateLocked = false,
    objective = nil,
    refill = false,
    refillUsed = false,
    tool = nil,
    toolUsed = false,
    key = nil,
    lock = nil,
    hazard = nil,
    terminal = nil,
    exit = false,
    dynamicGroup = nil,
    dynamicActive = false,
    landmark = nil,
    salvage = false,
    vent = false,
    district = nil,
    tags = {},
  }
end

local function makeSystems()
  return {
    lights = { powered = false, cost = 1 },
    doors = { powered = false, cost = 1 },
    pumps = { powered = false, cost = 1 },
    vents = { powered = false, cost = 1 },
    decoy = { powered = false, cost = 1, cooldown = 0 },
    lift = { powered = false, cost = 2 },
  }
end

local function makeLevel(width, height, deck, config)
  local grid = {}

  for y = 1, height do
    grid[y] = {}
    for x = 1, width do
      grid[y][x] = makeWallCell()
    end
  end

  return {
    width = width,
    height = height,
    deck = deck or 1,
    config = config,
    profile = config and config.profile or layoutProfiles[1],
    grid = grid,
    rooms = {},
    routeRooms = {},
    modules = {},
    criticalPath = {},
    start = { x = floor(width / 2), y = floor(height / 2) },
    exit = nil,
    stairCount = 0,
    ladderCount = 0,
    terrainCounts = {},
    zoneCounts = {},
    distinctFloorHeights = 0,
    heightTransitionCount = 0,
    steepTransitionCount = 0,
    ceilingTransitionCount = 0,
    objectives = {},
    refills = {},
    toolCaches = {},
    gates = {},
    keys = {},
    exitKey = nil,
    locks = {},
    hazards = {},
    terminals = {},
    systems = makeSystems(),
    power = { available = 0, assigned = 0, temporary = 0 },
    minLiftRelays = 0,
    salvageRooms = {},
    salvageLocked = false,
    creatureSpawns = {},
    npcSpawns = {},
    districts = {},
    nests = {},
    signals = {},
    factions = {},
    ecologyEvents = {},
    cycleShelters = {},
    visitedMap = {},
    roomModifiers = {},
    branch = config and config.branch or normalizeBranch(nil, deck),
    biomeProfile = config and config.biomeProfile or Level.biomeProfiles.cryo_vault,
    liftRequired = false,
    liftAuthorized = true,
    scanRevealed = false,
    validation = {},
  }
end

function Level.cellAtCell(level, x, y)
  if not level or x < 1 or y < 1 or x > level.width or y > level.height then
    return nil
  end
  return level.grid[y][x]
end

function Level.cellAtWorld(level, worldX, worldY)
  return Level.cellAtCell(level, floor(worldX), floor(worldY))
end

function Level.isBlocked(cell)
  return cell == nil or cell.solid or cell.gateLocked or (cell.lock and cell.lock.locked)
end

function Level.isHazardActive(cell)
  return cell and cell.hazard and cell.hazard.active and not cell.hazard.suppressed
end

local function carveCell(level, x, y, kind, light, terrain, zone)
  if x <= 1 or y <= 1 or x >= level.width or y >= level.height then
    return
  end

  local style = zoneStyle(kind or zone or "hall")
  local cell = level.grid[y][x]
  cell.solid = false
  cell.floor = Level.floorHeight
  cell.ceiling = Level.ceilingHeight
  cell.kind = kind or "hall"
  cell.light = light or style.light or 0.55
  cell.stair = false
  cell.ladder = kind == "ladder" or terrain == "ladder"
  cell.terrain = terrain or style.terrain or "stone"
  cell.zone = zone or kind or "hall"
end

local function carveBrush(level, centerX, centerY, radius, kind, light, terrain, zone)
  for y = centerY - radius, centerY + radius do
    for x = centerX - radius, centerX + radius do
      if abs(x - centerX) + abs(y - centerY) <= radius + 1 then
        carveCell(level, x, y, kind, light, terrain, zone)
      end
    end
  end
end

local function carveRect(level, x, y, width, height, kind, light, terrain, zone)
  for yy = y, y + height - 1 do
    for xx = x, x + width - 1 do
      carveCell(level, xx, yy, kind, light, terrain, zone)
    end
  end
end

local function tagCell(level, x, y, tag)
  local cell = Level.cellAtCell(level, x, y)
  if cell then
    cell.tags = cell.tags or {}
    cell.tags[tag] = true
  end
  return cell
end

local function addLevelSignal(level, x, y, kind, strength, source)
  local cell = Level.cellAtCell(level, x, y)
  if not cell or cell.solid then
    return nil
  end

  cell.signal = kind
  cell.tags = cell.tags or {}
  cell.tags.signal = true
  cell.tags[kind] = true

  local signal = {
    kind = kind,
    x = x + 0.5,
    y = y + 0.5,
    strength = strength or 1,
    source = source or "level",
    discovered = false,
  }
  level.signals[#level.signals + 1] = signal
  return signal
end

local function addDistrict(level, kind, room, role)
  if not room then
    return nil
  end

  local district = {
    id = #level.districts + 1,
    kind = kind,
    rooms = { room },
    role = role or kind,
    cx = room.cx,
    cy = room.cy,
  }

  level.districts[#level.districts + 1] = district
  room.district = kind
  room.districtId = district.id
  room.role = role or room.role or "route"

  for y = room.y, room.y + room.height - 1 do
    for x = room.x, room.x + room.width - 1 do
      local cell = Level.cellAtCell(level, x, y)
      if cell and not cell.solid then
        cell.district = kind
        cell.tags = cell.tags or {}
        cell.tags[kind] = true
        cell.tags[role or kind] = true
      end
    end
  end

  return district
end

local function cloneConnectors(connectors)
  local copy = {}

  for key, value in pairs(connectors or {}) do
    copy[key] = value
  end

  return copy
end

local function roomOverlaps(level, x, y, width, height, padding)
  padding = padding or 1

  if x <= 1 or y <= 1 or x + width - 1 >= level.width or y + height - 1 >= level.height then
    return true
  end

  for _, room in ipairs(level.rooms) do
    if x - padding <= room.x + room.width - 1
      and x + width - 1 + padding >= room.x
      and y - padding <= room.y + room.height - 1
      and y + height - 1 + padding >= room.y then
      return true
    end
  end

  return false
end

local function addRoomAt(level, x, y, width, height, kind, route, template)
  if roomOverlaps(level, x, y, width, height, 1) then
    return nil
  end

  local style = zoneStyle(kind)
  local light = style.light or 0.55

  carveRect(level, x, y, width, height, kind, light, style.terrain, kind)

  local room = {
    x = x,
    y = y,
    width = width,
    height = height,
    cx = x + floor(width / 2),
    cy = y + floor(height / 2),
    floor = Level.floorHeight,
    kind = kind,
    terrain = style.terrain,
    light = light,
    ceiling = Level.ceilingHeight,
    route = route or false,
    template = template and template.id or kind,
    connectors = cloneConnectors(template and template.connectors),
  }

  level.rooms[#level.rooms + 1] = room
  level.modules[#level.modules + 1] = room
  if route then
    level.routeRooms[#level.routeRooms + 1] = room
    level.criticalPath[#level.criticalPath + 1] = room
  end
  return room
end

local function addRoom(level, centerX, centerY, width, height, kind, route)
  local x = U.clamp(floor(centerX - width / 2), 2, level.width - width)
  local y = U.clamp(floor(centerY - height / 2), 2, level.height - height)
  local style = zoneStyle(kind)
  local light = style.light or 0.55

  carveRect(level, x, y, width, height, kind, light, style.terrain, kind)

  local room = {
    x = x,
    y = y,
    width = width,
    height = height,
    cx = x + floor(width / 2),
    cy = y + floor(height / 2),
    floor = Level.floorHeight,
    kind = kind,
    terrain = style.terrain,
    light = light,
    ceiling = Level.ceilingHeight,
    route = route or false,
    template = kind,
    connectors = { north = true, east = true, south = true, west = true },
  }

  level.rooms[#level.rooms + 1] = room
  level.modules[#level.modules + 1] = room
  if route then
    level.routeRooms[#level.routeRooms + 1] = room
    level.criticalPath[#level.criticalPath + 1] = room
  end
  return room
end

local function addJitteredRoom(level, centerX, centerY, widthRange, heightRange, kind, route)
  return addRoom(
    level,
    centerX + love.math.random(-2, 2),
    centerY + love.math.random(-2, 2),
    randomRange(widthRange),
    randomRange(heightRange),
    kind,
    route
  )
end

local function appendLine(points, x1, y1, x2, y2)
  if x1 ~= x2 then
    local step = x1 < x2 and 1 or -1
    for x = x1, x2, step do
      points[#points + 1] = { x, y1 }
    end
  end

  if y1 ~= y2 then
    local step = y1 < y2 and 1 or -1
    for y = y1 + step, y2, step do
      points[#points + 1] = { x2, y }
    end
  end
end

local function carvePolyline(level, vertices, width, zone, terrain)
  local points = {}

  for i = 1, #vertices - 1 do
    appendLine(points, vertices[i][1], vertices[i][2], vertices[i + 1][1], vertices[i + 1][2])
  end

  for _, point in ipairs(points) do
    carveBrush(level, point[1], point[2], width or 1, "hall", 0.52, terrain or "stone", zone or "passage")
  end

  return points
end

local function connectRooms(level, a, b, width, zone, terrain)
  local bend

  if love.math.random() < 0.5 then
    bend = { b.cx, a.cy }
  else
    bend = { a.cx, b.cy }
  end

  return carvePolyline(level, {
    { a.cx, a.cy },
    bend,
    { b.cx, b.cy },
  }, width or 1, zone or "passage", terrain or "stone")
end

local function setTerrain(level, x, y, terrain, light, kind, zone)
  local cell = Level.cellAtCell(level, x, y)

  if not cell or cell.solid then
    return
  end

  cell.floor = Level.floorHeight
  cell.ceiling = Level.ceilingHeight
  cell.terrain = terrain or cell.terrain
  cell.light = light or cell.light
  cell.kind = kind or cell.kind
  cell.zone = zone or cell.zone
  cell.stair = false
  cell.ladder = terrain == "ladder" or kind == "ladder"
end

local function setSolidFeature(level, x, y, kind, light)
  if x <= 1 or y <= 1 or x >= level.width or y >= level.height then
    return
  end

  local cell = level.grid[y][x]
  cell.solid = true
  cell.floor = Level.floorHeight
  cell.ceiling = Level.ceilingHeight
  cell.kind = kind or "feature"
  cell.light = light or 0.38
  cell.stair = false
  cell.ladder = false
  cell.terrain = "stone"
  cell.zone = "feature"
  cell.gate = false
  cell.gateLocked = false
  cell.objective = nil
  cell.refill = false
  cell.refillUsed = false
  cell.tool = nil
  cell.toolUsed = false
  cell.key = nil
  cell.lock = nil
  cell.hazard = nil
  cell.terminal = nil
  cell.exit = false
  cell.dynamicGroup = nil
  cell.dynamicActive = false
  cell.landmark = nil
  cell.salvage = false
  cell.vent = false
end

local function preserveRoomSpine(room, x, y)
  return abs(x - room.cx) <= 1 or abs(y - room.cy) <= 1
end

local function scatterTerrain(level, room, terrain, chance, light, kind)
  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      if not preserveRoomSpine(room, x, y) and love.math.random() < chance then
        setTerrain(level, x, y, terrain, light, kind)
      end
    end
  end
end

local function carveRoomAlcove(level, room)
  local direction = directions[love.math.random(#directions)]
  local width = love.math.random(2, 4)
  local depth = love.math.random(2, 5)
  local x
  local y

  if direction.name == "north" then
    x = U.clamp(room.cx + love.math.random(-floor(room.width / 3), floor(room.width / 3)), room.x + 2, room.x + room.width - width - 1)
    y = room.y - depth
    carveRect(level, x, y, width, depth + 1, room.kind, room.light, room.terrain, room.kind)
  elseif direction.name == "south" then
    x = U.clamp(room.cx + love.math.random(-floor(room.width / 3), floor(room.width / 3)), room.x + 2, room.x + room.width - width - 1)
    y = room.y + room.height - 1
    carveRect(level, x, y, width, depth + 1, room.kind, room.light, room.terrain, room.kind)
  elseif direction.name == "east" then
    x = room.x + room.width - 1
    y = U.clamp(room.cy + love.math.random(-floor(room.height / 3), floor(room.height / 3)), room.y + 2, room.y + room.height - width - 1)
    carveRect(level, x, y, depth + 1, width, room.kind, room.light, room.terrain, room.kind)
  else
    x = room.x - depth
    y = U.clamp(room.cy + love.math.random(-floor(room.height / 3), floor(room.height / 3)), room.y + 2, room.y + room.height - width - 1)
    carveRect(level, x, y, depth + 1, width, room.kind, room.light, room.terrain, room.kind)
  end
end

local function notchRoomCorners(level, room)
  if room.width < 9 or room.height < 9 then
    return
  end

  local corners = {
    { room.x + 1, room.y + 1 },
    { room.x + room.width - 3, room.y + 1 },
    { room.x + 1, room.y + room.height - 3 },
    { room.x + room.width - 3, room.y + room.height - 3 },
  }
  local corner = corners[love.math.random(#corners)]

  for y = corner[2], corner[2] + 1 do
    for x = corner[1], corner[1] + 1 do
      if not preserveRoomSpine(room, x, y) then
        setSolidFeature(level, x, y, "collapsed wall", 0.34)
      end
    end
  end
end

local function mutateRoomShape(level, room)
  local profile = level.profile or layoutProfiles[1]
  local alcoves = profile.alcoves or 1

  if room.kind == "atrium" then
    alcoves = max(1, alcoves - 1)
  end

  for _ = 1, alcoves do
    if love.math.random() < 0.72 then
      carveRoomAlcove(level, room)
    end
  end

  if love.math.random() < 0.34 then
    notchRoomCorners(level, room)
  end
end

local function addFoundryFeatures(level, room)
  for y = room.y + 2, room.y + room.height - 3 do
    for x = room.x + 2, room.x + room.width - 3 do
      if x % 4 == 0 then
        setTerrain(level, x, y, "catwalk", 0.68, "catwalk")
      elseif y % 5 == 0 and love.math.random() < 0.42 then
        setTerrain(level, x, y, "slag", 0.72, "slag")
      end
    end
  end
end

local function addArchiveFeatures(level, room)
  for x = room.x + 3, room.x + room.width - 3, 4 do
    for y = room.y + 2, room.y + room.height - 3 do
      if not preserveRoomSpine(room, x, y) and love.math.random() < 0.68 then
        setSolidFeature(level, x, y, "stacks", 0.35)
      end
    end
  end

  scatterTerrain(level, room, "dust", 0.36, 0.5)
end

local function addCisternFeatures(level, room)
  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      if preserveRoomSpine(room, x, y) then
        setTerrain(level, x, y, "catwalk", 0.64, "catwalk")
      elseif love.math.random() < 0.72 then
        setTerrain(level, x, y, "water", 0.48, "cistern")
      end
    end
  end
end

local function addOvergrowthFeatures(level, room)
  scatterTerrain(level, room, "moss", 0.6, 0.68)

  for _ = 1, 5 do
    local x = love.math.random(room.x + 2, room.x + room.width - 3)
    local y = love.math.random(room.y + 2, room.y + room.height - 3)

    if not preserveRoomSpine(room, x, y) then
      setSolidFeature(level, x, y, "root mass", 0.46)
    end
  end
end

local function addQuarryFeatures(level, room)
  scatterTerrain(level, room, "rubble", 0.54, 0.54, "rubble")

  for _ = 1, 5 do
    local x = love.math.random(room.x + 2, room.x + room.width - 3)
    local y = love.math.random(room.y + 2, room.y + room.height - 3)

    if not preserveRoomSpine(room, x, y) then
      setSolidFeature(level, x, y, "boulder", 0.4)
    end
  end
end

local function addObservatoryFeatures(level, room)
  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      local distance = sqrt((x - room.cx) ^ 2 + (y - room.cy) ^ 2)

      if distance < min(room.width, room.height) * 0.25 then
        setTerrain(level, x, y, "glass", 0.76, "dais")
      elseif distance > min(room.width, room.height) * 0.4 and love.math.random() < 0.28 then
        setTerrain(level, x, y, "rubble", 0.58, "broken rim")
      end
    end
  end
end

local function addMachineFeatures(level, room)
  for y = room.y + 2, room.y + room.height - 3 do
    for x = room.x + 2, room.x + room.width - 3 do
      if y % 4 == 0 then
        setTerrain(level, x, y, "grate", 0.66, "service deck")
      elseif x % 5 == 0 and not preserveRoomSpine(room, x, y) then
        setSolidFeature(level, x, y, "machinery", 0.4)
      end
    end
  end
end

local function addBridgeFeatures(level, room)
  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      if preserveRoomSpine(room, x, y) then
        setTerrain(level, x, y, "catwalk", 0.66, "bridge")
      elseif love.math.random() < 0.36 then
        setTerrain(level, x, y, "rubble", 0.46, "rubble")
      end
    end
  end
end

local function restoreRoomCenter(level, room)
  local style = zoneStyle(room.kind)

  for y = room.cy - 1, room.cy + 1 do
    for x = room.cx - 1, room.cx + 1 do
      carveCell(level, x, y, room.kind, max(room.light or 0.55, 0.62), style.terrain, room.kind)
    end
  end
end

local function decorateRoom(level, room)
  if room.kind == "lower foundry" then
    addFoundryFeatures(level, room)
  elseif room.kind == "archive" then
    addArchiveFeatures(level, room)
  elseif room.kind == "cistern" then
    addCisternFeatures(level, room)
  elseif room.kind == "overgrown court" then
    addOvergrowthFeatures(level, room)
  elseif room.kind == "quarry" then
    addQuarryFeatures(level, room)
  elseif room.kind == "observatory" then
    addObservatoryFeatures(level, room)
  elseif room.kind == "machine shaft" then
    addMachineFeatures(level, room)
  elseif room.kind == "bridgeworks" then
    addBridgeFeatures(level, room)
  elseif room.kind == "annex" or room.kind == "chamber" then
    scatterTerrain(level, room, "rubble", 0.16, 0.54, "rubble")
  end

  restoreRoomCenter(level, room)
end

local function addColumns(level)
  for _, room in ipairs(level.rooms) do
    if not room.route and room.width >= 8 and room.height >= 8 then
      for y = room.y + 3, room.y + room.height - 4, 4 do
        for x = room.x + 3, room.x + room.width - 4, 5 do
          local centerDistance = sqrt((x - room.cx) ^ 2 + (y - room.cy) ^ 2)

          if centerDistance > 3.2 and love.math.random() < 0.28 then
            setSolidFeature(level, x, y, "column", 0.42)
          end
        end
      end
    end
  end
end

local function countFeatures(level)
  local stairCount = 0
  local ladderCount = 0
  local terrainCounts = {}
  local zoneCounts = {}
  local floorHeights = {}
  local floorHeightCount = 0
  local heightTransitions = 0
  local steepTransitions = 0
  local ceilingTransitions = 0

  for y = 1, level.height do
    for x = 1, level.width do
      local cell = level.grid[y][x]
      if not cell.solid then
        terrainCounts[cell.terrain] = (terrainCounts[cell.terrain] or 0) + 1
        zoneCounts[cell.zone] = (zoneCounts[cell.zone] or 0) + 1

        local floorKey = string.format("%.2f", cell.floor or 0)
        if not floorHeights[floorKey] then
          floorHeights[floorKey] = true
          floorHeightCount = floorHeightCount + 1
        end

        if cell.stair then
          stairCount = stairCount + 1
        end
        if cell.ladder then
          ladderCount = ladderCount + 1
        end

        for _, neighbor in ipairs(metricNeighbors) do
          local other = Level.cellAtCell(level, x + neighbor[1], y + neighbor[2])
          if other and not other.solid then
            local floorDelta = abs((other.floor or 0) - (cell.floor or 0))
            if floorDelta > 0.04 then
              heightTransitions = heightTransitions + 1
            end
            if floorDelta > Level.maxStepHeight then
              steepTransitions = steepTransitions + 1
            end
            if abs((other.ceiling or 0) - (cell.ceiling or 0)) > 0.04 then
              ceilingTransitions = ceilingTransitions + 1
            end
          end
        end
      end
    end
  end

  level.stairCount = stairCount
  level.ladderCount = ladderCount
  level.terrainCounts = terrainCounts
  level.zoneCounts = zoneCounts
  level.distinctFloorHeights = floorHeightCount
  level.heightTransitionCount = heightTransitions
  level.steepTransitionCount = steepTransitions
  level.ceilingTransitionCount = ceilingTransitions
end

function Level.canTraverseCells(level, ax, ay, bx, by)
  local a = Level.cellAtCell(level, ax, ay)
  local b = Level.cellAtCell(level, bx, by)

  if Level.isBlocked(a) or Level.isBlocked(b) then
    return false
  end

  if ax == bx and ay == by then
    return true
  end

  local heightDelta = abs((b.floor or 0) - (a.floor or 0))
  return heightDelta <= Level.maxStepHeight or (a.ladder and b.ladder)
end

function Level.isWalkableCell(level, x, y)
  local cell = Level.cellAtCell(level, x, y)
  return cell ~= nil and not Level.isBlocked(cell)
end

function Level.farthestCellFrom(level, startX, startY)
  local queue = { { startX, startY } }
  local head = 1
  local visited = { [U.keyOf(startX, startY)] = true }
  local farthest = { x = startX, y = startY, distance = 0 }
  local distances = { [U.keyOf(startX, startY)] = 0 }

  while head <= #queue do
    local current = queue[head]
    head = head + 1
    local x, y = current[1], current[2]
    local distance = distances[U.keyOf(x, y)] or 0

    if distance > farthest.distance then
      farthest = { x = x, y = y, distance = distance }
    end

    for _, neighbor in ipairs(U.neighbors) do
      local nx, ny = x + neighbor[1], y + neighbor[2]
      local neighborKey = U.keyOf(nx, ny)

      if not visited[neighborKey] and Level.canTraverseCells(level, x, y, nx, ny) then
        visited[neighborKey] = true
        distances[neighborKey] = distance + 1
        queue[#queue + 1] = { nx, ny }
      end
    end
  end

  return farthest, visited
end

local function heuristic(ax, ay, bx, by)
  return abs(ax - bx) + abs(ay - by)
end

local function reconstructPath(cameFrom, startX, startY, goalX, goalY)
  local path = {}
  local current = { x = goalX, y = goalY }

  while current and not (current.x == startX and current.y == startY) do
    table.insert(path, 1, {
      x = current.x + 0.5,
      y = current.y + 0.5,
      cellX = current.x,
      cellY = current.y,
    })
    current = cameFrom[U.keyOf(current.x, current.y)]
  end

  return path
end

function Level.findPath(level, startX, startY, goalX, goalY)
  if not Level.isWalkableCell(level, startX, startY) or not Level.isWalkableCell(level, goalX, goalY) then
    return {}
  end

  if startX == goalX and startY == goalY then
    return {}
  end

  local open = {
    {
      x = startX,
      y = startY,
      g = 0,
      f = heuristic(startX, startY, goalX, goalY),
    },
  }
  local cameFrom = {}
  local gScore = { [U.keyOf(startX, startY)] = 0 }
  local closed = {}

  while #open > 0 do
    local bestIndex = 1

    for i = 2, #open do
      if open[i].f < open[bestIndex].f then
        bestIndex = i
      end
    end

    local current = table.remove(open, bestIndex)
    local currentKey = U.keyOf(current.x, current.y)

    if not closed[currentKey] then
      if current.x == goalX and current.y == goalY then
        return reconstructPath(cameFrom, startX, startY, goalX, goalY)
      end

      closed[currentKey] = true

      for _, neighbor in ipairs(U.neighbors) do
        local nx, ny = current.x + neighbor[1], current.y + neighbor[2]
        local neighborKey = U.keyOf(nx, ny)

        if Level.canTraverseCells(level, current.x, current.y, nx, ny) and not closed[neighborKey] then
          local toCell = Level.cellAtCell(level, nx, ny)
          local terrainCost = 1 / max(0.35, Level.terrainSpeed[toCell.terrain] or 1)
          local ladderCost = toCell.ladder and 0.2 or 0
          local tentativeG = current.g + terrainCost + ladderCost

          if tentativeG < (gScore[neighborKey] or math.huge) then
            cameFrom[neighborKey] = { x = current.x, y = current.y }
            gScore[neighborKey] = tentativeG
            open[#open + 1] = {
              x = nx,
              y = ny,
              g = tentativeG,
              f = tentativeG + heuristic(nx, ny, goalX, goalY),
            }
          end
        end
      end
    end
  end

  return {}
end

function Level.lineOfSight(level, ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local distance = sqrt(dx * dx + dy * dy)

  if distance <= 0 then
    return true
  end

  local steps = math.ceil(distance / 0.08)

  for i = 1, steps do
    local t = i / steps
    local x = ax + dx * t
    local y = ay + dy * t

    if Level.isBlocked(Level.cellAtWorld(level, x, y)) then
      return false
    end
  end

  return true
end

local function markObjective(level, room, id)
  local cell = Level.cellAtCell(level, room.cx, room.cy)
  if not cell or cell.solid then
    return
  end

  cell.objective = {
    id = id,
    label = objectiveLabels[id] or ("RELAY " .. id),
    collected = false,
  }
  cell.kind = "relay"
  cell.terrain = "glass"
  cell.light = max(cell.light or 0.5, 0.9)
  cell.landmark = "relay"
  level.objectives[#level.objectives + 1] = { x = room.cx, y = room.cy, room = room, cell = cell, id = id }
end

local function markRefill(level, room)
  for _ = 1, 16 do
    local x = U.clamp(room.cx + love.math.random(-3, 3), room.x + 1, room.x + room.width - 2)
    local y = U.clamp(room.cy + love.math.random(-3, 3), room.y + 1, room.y + room.height - 2)
    local cell = Level.cellAtCell(level, x, y)

    if cell and not cell.solid and not cell.objective and not cell.gate and not cell.ladder and not cell.refill and not cell.terminal then
      cell.refill = true
      cell.refillUsed = false
      cell.kind = "oil cache"
      cell.light = max(cell.light or 0.5, 0.76)
      level.refills[#level.refills + 1] = { x = x, y = y, cell = cell }
      return true
    end
  end

  return false
end

local function markToolCache(level, room, tool, id)
  for _ = 1, 18 do
    local x = U.clamp(room.cx + love.math.random(-3, 3), room.x + 1, room.x + room.width - 2)
    local y = U.clamp(room.cy + love.math.random(-3, 3), room.y + 1, room.y + room.height - 2)
    local cell = Level.cellAtCell(level, x, y)

    if cell and not cell.solid and not cell.objective and not cell.gate and not cell.ladder and not cell.refill and not cell.key and not cell.terminal and not cell.exit and not cell.tool then
      cell.tool = {
        kind = tool,
        id = id,
        salvage = id >= 20 and 2 or 1,
        contaminated = level.biomeProfile and level.biomeProfile.district == "waste_artery" or false,
        mimic = level.biomeProfile and level.biomeProfile.district == "signal_catacombs" and id % 2 == 0 or false,
      }
      cell.toolUsed = false
      cell.kind = tool .. " cache"
      cell.light = max(cell.light or 0.5, 0.78)
      cell.landmark = "tool"
      cell.salvage = true
      level.toolCaches[#level.toolCaches + 1] = { x = x, y = y, cell = cell, kind = tool, id = id, room = room }
      return true
    end
  end

  return false
end

local function markKey(level, room, id, kind)
  kind = kind or "small"
  for _ = 1, 18 do
    local x = U.clamp(room.cx + love.math.random(-3, 3), room.x + 1, room.x + room.width - 2)
    local y = U.clamp(room.cy + love.math.random(-3, 3), room.y + 1, room.y + room.height - 2)
    local cell = Level.cellAtCell(level, x, y)

    if cell and not cell.solid and not cell.objective and not cell.gate and not cell.ladder and not cell.refill and not cell.key and not cell.terminal and not cell.exit then
      cell.key = {
        id = id,
        kind = kind,
        label = kind == "exit" and "EXIT KEY" or "SMALL KEY",
        collected = false,
      }
      cell.kind = kind == "exit" and "exit key" or "key"
      cell.light = max(cell.light or 0.5, kind == "exit" and 0.9 or 0.82)
      cell.landmark = "key"
      local key = { x = x, y = y, cell = cell, id = id, kind = kind }
      level.keys[#level.keys + 1] = key
      if kind == "exit" then
        level.exitKey = key
      end
      return true
    end
  end

  return false
end

local function markLadder(level, room)
  local cell = Level.cellAtCell(level, room.cx, room.cy)

  if not cell or cell.solid or cell.objective or cell.gate then
    return false
  end

  cell.kind = "ladder"
  cell.terrain = "ladder"
  cell.ladder = true
  cell.light = max(cell.light or 0.5, 0.78)
  cell.zone = "shaft"
  cell.landmark = "ladder"
  return true
end

local function markExit(level, room)
  local cell = Level.cellAtCell(level, room.cx, room.cy)

  if not cell or cell.solid or cell.objective or cell.gate then
    return false
  end

  cell.exit = true
  cell.kind = "exit shaft"
  cell.terrain = "ladder"
  cell.ladder = true
  cell.light = max(cell.light or 0.5, 0.86)
  cell.zone = "shaft"
  cell.landmark = "exit"
  level.exit = { x = room.cx, y = room.cy, room = room, cell = cell }
  return true
end

local function markHazard(level, room, id)
  local kinds = {
    { kind = "ember", terrain = "slag", light = 0.78 },
    { kind = "pit", terrain = "rubble", light = 0.42 },
    { kind = "wire", terrain = "grate", light = 0.68 },
  }
  local spec = kinds[((id - 1) % #kinds) + 1]

  for _ = 1, 18 do
    local x = love.math.random(room.x + 1, room.x + room.width - 2)
    local y = love.math.random(room.y + 1, room.y + room.height - 2)
    local cell = Level.cellAtCell(level, x, y)

    if cell and not cell.solid and not preserveRoomSpine(room, x, y) and not cell.objective and not cell.gate and not cell.ladder and not cell.refill and not cell.key and not cell.terminal and not cell.exit and not cell.hazard then
      cell.hazard = { id = id, kind = spec.kind, active = true, suppressed = false }
      cell.terrain = spec.terrain
      cell.kind = spec.kind
      cell.light = max(cell.light or 0.5, spec.light)
      level.hazards[#level.hazards + 1] = { x = x, y = y, cell = cell, id = id, kind = spec.kind, room = room }
      return true
    end
  end

  return false
end

local function markVent(level, room)
  for _ = 1, 12 do
    local x = U.clamp(room.cx + love.math.random(-4, 4), room.x + 1, room.x + room.width - 2)
    local y = U.clamp(room.cy + love.math.random(-4, 4), room.y + 1, room.y + room.height - 2)
    local cell = Level.cellAtCell(level, x, y)

    if cell and not cell.solid and not cell.objective and not cell.gate and not cell.ladder and not cell.refill and not cell.key and not cell.terminal and not cell.exit then
      cell.vent = true
      cell.kind = "vent"
      cell.terrain = "grate"
      cell.light = max(cell.light or 0.5, 0.68)
      cell.landmark = "vent"
      return true
    end
  end

  return false
end

local function markTerminal(level, room, id, command, target)
  for _ = 1, 20 do
    local x = U.clamp(room.cx + love.math.random(-3, 3), room.x + 1, room.x + room.width - 2)
    local y = U.clamp(room.cy + love.math.random(-3, 3), room.y + 1, room.y + room.height - 2)
    local cell = Level.cellAtCell(level, x, y)

    if cell and not cell.solid and not cell.objective and not cell.gate and not cell.ladder and not cell.refill and not cell.key and not cell.lock and not cell.hazard and not cell.terminal and not cell.exit then
      local terminal = {
        id = id,
        label = string.format("T%02d", id),
        command = command,
        target = target,
        used = false,
        logs = { "LINK READY", "ACCEPTS " .. command },
        room = room,
      }

      cell.terminal = terminal
      cell.kind = "terminal"
      cell.terrain = "glass"
      cell.light = max(cell.light or 0.5, 0.84)
      cell.landmark = "terminal"
      level.terminals[#level.terminals + 1] = { x = x, y = y, cell = cell, room = room, terminal = terminal, id = id, command = command, target = target }
      return true
    end
  end

  return false
end

function Level.unlockTerminalTarget(level, terminal)
  local target = terminal and terminal.target

  if target and target.type == "lock" and level.locks[target.index] then
    local lock = level.locks[target.index]
    if lock.cell.lock.locked then
      lock.cell.lock.locked = false
      terminal.used = true
      return true, "LOCK " .. lock.id .. " OPEN"
    end
    return false, "LOCK ALREADY OPEN"
  end

  if target and target.type == "gate" and level.gates[target.index] then
    local gate = level.gates[target.index]
    if gate.cell.gateLocked then
      gate.cell.gateLocked = false
      terminal.used = true
      return true, "SEAL OPEN"
    end
    return false, "SEAL ALREADY OPEN"
  end

  for _, lock in ipairs(level.locks or {}) do
    if lock.cell.lock.locked then
      lock.cell.lock.locked = false
      terminal.used = true
      return true, "LOCK " .. lock.id .. " OPEN"
    end
  end

  for _, gate in ipairs(level.gates or {}) do
    if gate.cell.gateLocked then
      gate.cell.gateLocked = false
      terminal.used = true
      return true, "SEAL OPEN"
    end
  end

  return false, "NO LOCKED TARGET"
end

function Level.purgeTerminalHazards(level, terminal)
  local purged = 0
  local room = terminal and terminal.room
  local systems = level.systems or {}
  local pumps = systems.pumps and systems.pumps.powered
  local vents = systems.vents and systems.vents.powered

  for _, hazard in ipairs(level.hazards or {}) do
    if hazard.cell.hazard and hazard.cell.hazard.active and (hazard.room == room or hazard.cell.zone == (room and room.kind)) then
      local kind = hazard.cell.hazard.kind
      if pumps and (kind == "wire" or kind == "pit") then
        hazard.cell.hazard.suppressed = true
        hazard.cell.light = min(hazard.cell.light or 0.5, 0.42)
        purged = purged + 1
      elseif vents and kind == "ember" then
        hazard.cell.hazard.suppressed = true
        hazard.cell.light = min(hazard.cell.light or 0.5, 0.42)
        purged = purged + 1
      end
    end
  end

  if purged == 0 then
    for _, hazard in ipairs(level.hazards or {}) do
      if hazard.cell.hazard and hazard.cell.hazard.active then
        hazard.cell.hazard.suppressed = true
        hazard.cell.light = min(hazard.cell.light or 0.5, 0.42)
        purged = purged + 1
        if purged >= ((pumps or vents) and 3 or 1) then
          break
        end
      end
    end
  end

  if purged > 0 then
    terminal.used = true
    return true, string.format("PURGED %02d HAZARDS", purged)
  end

  return false, "NO ACTIVE HAZARDS"
end

local function markDynamicCells(level, room)
  local marked = 0

  for _ = 1, 16 do
    if marked >= 3 then
      break
    end

    local x = love.math.random(room.x + 1, room.x + room.width - 2)
    local y = love.math.random(room.y + 1, room.y + room.height - 2)
    local cell = Level.cellAtCell(level, x, y)

    if cell and not cell.solid and not preserveRoomSpine(room, x, y) and not cell.objective and not cell.gate and not cell.ladder and not cell.refill and not cell.key and not cell.terminal and not cell.exit then
      cell.dynamicGroup = "relays"
      cell.dynamicActive = false
      cell.light = min(cell.light or 0.5, 0.36)
      marked = marked + 1
    end
  end
end

function Level.activateDynamics(level, group)
  for y = 1, level.height do
    for x = 1, level.width do
      local cell = level.grid[y][x]
      if cell.dynamicGroup == group and not cell.dynamicActive then
        cell.dynamicActive = true
        cell.light = max(cell.light or 0.5, 0.82)
        if cell.terrain == "stone" then
          cell.terrain = "glass"
        end
      end
    end
  end
end

local function findGatePoint(level, points)
  local mid = floor(#points / 2)

  for offset = 0, mid do
    for _, index in ipairs({ mid - offset, mid + offset }) do
      local point = points[index]
      if point then
        local cell = Level.cellAtCell(level, point[1], point[2])
        if cell and not cell.solid and not cell.objective and not cell.refill and not cell.ladder and not cell.key and not cell.lock and not cell.hazard and not cell.terminal and not cell.exit then
          if not (point[1] == level.start.x and point[2] == level.start.y) then
            return point
          end
        end
      end
    end
  end

  return nil
end

local function markShortcutGate(level, points, required)
  if #points < 5 then
    return
  end

  local point = findGatePoint(level, points)
  if not point then
    return
  end

  local cell = Level.cellAtCell(level, point[1], point[2])
  cell.gate = true
  cell.gateLocked = true
  cell.kind = "sealed gate"
  cell.light = 0.88
  cell.terrain = "stone"
  cell.zone = "seal"
  level.gates[#level.gates + 1] = { x = point[1], y = point[2], cell = cell, required = required or 999 }
end

local function markLock(level, points, id)
  if #points < 5 then
    return
  end

  local point = findGatePoint(level, points)
  if not point then
    return
  end

  local cell = Level.cellAtCell(level, point[1], point[2])
  cell.gate = true
  cell.gateLocked = false
  cell.lock = {
    id = id,
    locked = true,
  }
  cell.kind = "lock"
  cell.light = 0.82
  cell.terrain = "stone"
  cell.zone = "lock"
  level.locks[#level.locks + 1] = { x = point[1], y = point[2], cell = cell, id = id }
end

function Level.setGatesLocked(level, locked)
  for _, gate in ipairs(level.gates or {}) do
    gate.cell.gateLocked = locked
  end
end

function Level.setLocksLocked(level, locked)
  for _, lock in ipairs(level.locks or {}) do
    lock.cell.lock.locked = locked
  end
end

function Level.powerUsed(level)
  local used = 0

  for _, name in ipairs(systemOrder) do
    local system = level.systems and level.systems[name]
    if system and system.powered then
      used = used + (system.cost or 1)
    end
  end

  if level.power then
    level.power.assigned = used
  end

  return used
end

function Level.powerCapacity(level)
  local power = level.power or {}
  return (power.available or 0) + (power.temporary or 0)
end

function Level.applySystemEffects(level)
  local systems = level.systems or {}
  local lights = systems.lights and systems.lights.powered
  local doors = systems.doors and systems.doors.powered
  local pumps = systems.pumps and systems.pumps.powered
  local vents = systems.vents and systems.vents.powered

  for _, gate in ipairs(level.gates or {}) do
    gate.cell.gateLocked = not doors
    gate.cell.light = doors and 0.72 or 0.88
  end

  level.liftAuthorized = (systems.lift and systems.lift.powered) or false

  for y = 1, level.height do
    for x = 1, level.width do
      local cell = level.grid[y][x]
      if not cell.solid then
        if cell.dynamicGroup == "relays" or cell.terminal or cell.vent then
          cell.dynamicActive = lights or vents or cell.dynamicActive
          if lights then
            cell.light = max(cell.light or 0.5, 0.76)
          elseif cell.dynamicGroup == "relays" and not cell.dynamicActive then
            cell.light = min(cell.light or 0.5, 0.42)
          end
        end

        if cell.hazard then
          if cell.hazard.kind == "wire" then
            cell.hazard.suppressed = pumps
          elseif cell.hazard.kind == "ember" then
            cell.hazard.suppressed = pumps or vents
          elseif cell.hazard.kind == "pit" then
            cell.hazard.suppressed = false
          end
        end
      end
    end
  end

  Level.powerUsed(level)
end

function Level.setSystemPowered(level, name, powered)
  local system = level.systems and level.systems[name]
  if not system then
    return false, "UNKNOWN SYSTEM"
  end

  powered = powered ~= false
  if powered == system.powered then
    return true, string.upper(name) .. (powered and " ALREADY POWERED" or " ALREADY OFFLINE")
  end

  if powered then
    local used = Level.powerUsed(level)
    local capacity = Level.powerCapacity(level)
    if used + (system.cost or 1) > capacity then
      return false, "INSUFFICIENT POWER"
    end
  end

  system.powered = powered
  Level.applySystemEffects(level)
  return true, string.upper(name) .. (powered and " POWERED" or " OFFLINE")
end

function Level.toggleSystem(level, name)
  local system = level.systems and level.systems[name]
  if not system then
    return false, "UNKNOWN SYSTEM"
  end

  return Level.setSystemPowered(level, name, not system.powered)
end

local function setGateState(level, locked)
  local states = {}

  for i, gate in ipairs(level.gates or {}) do
    states[i] = gate.cell.gateLocked
    gate.cell.gateLocked = locked
  end

  return states
end

local function restoreGateState(level, states)
  for i, gate in ipairs(level.gates or {}) do
    gate.cell.gateLocked = states[i]
  end
end

local function setLockState(level, locked)
  local states = {}

  for i, lock in ipairs(level.locks or {}) do
    states[i] = lock.cell.lock.locked
    lock.cell.lock.locked = locked
  end

  return states
end

local function restoreLockState(level, states)
  for i, lock in ipairs(level.locks or {}) do
    lock.cell.lock.locked = states[i]
  end
end

local function reachableFromStart(level, gatesLocked, locksLocked)
  local states = setGateState(level, gatesLocked)
  local lockStates = setLockState(level, locksLocked == nil and gatesLocked or locksLocked)
  local farthest, visited = Level.farthestCellFrom(level, level.start.x, level.start.y)
  restoreLockState(level, lockStates)
  restoreGateState(level, states)

  local reachable = 0
  for _ in pairs(visited) do
    reachable = reachable + 1
  end

  return reachable, visited, farthest
end

local function countOpenCells(level, includeGates)
  local count = 0

  for y = 1, level.height do
    for x = 1, level.width do
      local cell = level.grid[y][x]
      if not cell.solid and (includeGates or not cell.gate) then
        count = count + 1
      end
    end
  end

  return count
end

local function countVisitedCells(level, visited, includeGates)
  local count = 0

  for y = 1, level.height do
    for x = 1, level.width do
      local cell = level.grid[y][x]
      if not cell.solid and (includeGates or not cell.gate) and visited[U.keyOf(x, y)] then
        count = count + 1
      end
    end
  end

  return count
end

local function countReachableObjectives(level, visited)
  local count = 0

  for _, objective in ipairs(level.objectives) do
    if visited[U.keyOf(objective.x, objective.y)] then
      count = count + 1
    end
  end

  return count
end

local function countReachableKeys(level, visited)
  local count = 0

  for _, key in ipairs(level.keys or {}) do
    if visited[U.keyOf(key.x, key.y)] then
      count = count + 1
    end
  end

  return count
end

local function countReachableTerminals(level, visited)
  local count = 0
  local liftReachable = false

  for _, terminal in ipairs(level.terminals or {}) do
    if visited[U.keyOf(terminal.x, terminal.y)] then
      count = count + 1
      if terminal.command == "LIFT" then
        liftReachable = true
      end
    end
  end

  return count, liftReachable
end

local function exitReachable(level, visited)
  return level.exit ~= nil and visited[U.keyOf(level.exit.x, level.exit.y)] == true
end

local function gateDegree(level, gate)
  local degree = 0

  for _, neighbor in ipairs(U.neighbors) do
    local nx, ny = gate.x + neighbor[1], gate.y + neighbor[2]
    if Level.canTraverseCells(level, gate.x, gate.y, nx, ny) then
      degree = degree + 1
    end
  end

  return degree
end

local function countUsableGates(level, visited)
  local reachable = 0
  local usable = 0
  local states = setGateState(level, false)

  for _, gate in ipairs(level.gates or {}) do
    if visited[U.keyOf(gate.x, gate.y)] then
      reachable = reachable + 1
    end
    if gateDegree(level, gate) >= 2 then
      usable = usable + 1
    end
  end

  restoreGateState(level, states)
  return reachable, usable
end

local function countUsableLocks(level, visited)
  local reachable = 0
  local usable = 0
  local states = setLockState(level, false)

  for _, lock in ipairs(level.locks or {}) do
    if visited[U.keyOf(lock.x, lock.y)] then
      reachable = reachable + 1
    end
    if gateDegree(level, lock) >= 2 then
      usable = usable + 1
    end
  end

  restoreLockState(level, states)
  return reachable, usable
end

local function countDistrictKinds(level)
  local seen = {}
  local count = 0

  for _, district in ipairs(level.districts or {}) do
    if district.kind and not seen[district.kind] then
      seen[district.kind] = true
      count = count + 1
    end
  end

  return count
end

local function compactRefills(level)
  local refills = {}

  for _, refill in ipairs(level.refills or {}) do
    if refill.cell and not refill.cell.solid and refill.cell.refill then
      refills[#refills + 1] = refill
    end
  end

  level.refills = refills
end

local function sealUnreachableCells(level)
  local states = setGateState(level, true)
  local lockStates = setLockState(level, true)
  local _, visited = Level.farthestCellFrom(level, level.start.x, level.start.y)
  restoreLockState(level, lockStates)
  restoreGateState(level, states)

  for y = 1, level.height do
    for x = 1, level.width do
      local cell = level.grid[y][x]
      if not cell.solid and not cell.gate and not cell.objective and not visited[U.keyOf(x, y)] then
        cell.solid = true
        cell.kind = "sealed void"
        cell.light = 0.28
        cell.stair = false
        cell.ladder = false
        cell.refill = false
        cell.refillUsed = false
        cell.tool = nil
        cell.toolUsed = false
        cell.key = nil
        cell.lock = nil
        cell.hazard = nil
        cell.terminal = nil
        cell.exit = false
        cell.dynamicGroup = nil
        cell.dynamicActive = false
        cell.landmark = nil
        cell.salvage = false
        cell.vent = false
      end
    end
  end

  compactRefills(level)
end

function Level.validate(level)
  countFeatures(level)

  local config = level.config or Level.deckConfigs[level.deck or 1] or Level.deckConfigs[1]
  local lockedReachable, lockedVisited, farthest = reachableFromStart(level, true, true)
  local unlockedReachable, unlockedVisited = reachableFromStart(level, false, false)
  local lockedOpenCells = countOpenCells(level, false)
  local unlockedOpenCells = countOpenCells(level, true)
  local lockedConnected = countVisitedCells(level, lockedVisited, false)
  local unlockedConnected = countVisitedCells(level, unlockedVisited, true)
  local keyReachable = countReachableKeys(level, lockedVisited)
  local exitOpenReachable = exitReachable(level, lockedVisited)
  local gateReachable, gateUsable = countUsableGates(level, unlockedVisited)
  local lockReachable, lockUsable = countUsableLocks(level, unlockedVisited)
  local districtKinds = countDistrictKinds(level)
  local failures = {}

  local function requireValid(condition, label)
    if not condition then
      failures[#failures + 1] = label
    end
  end

  requireValid(lockedReachable >= 360 + (level.deck or 1) * 40, "min-reachable")
  requireValid(lockedConnected == lockedOpenCells, "locked-connectivity")
  requireValid(unlockedConnected == unlockedOpenCells, "unlocked-connectivity")
  requireValid(#level.rooms >= (config.rooms or 12), "rooms")
  requireValid(#level.refills >= (config.refills or 5), "refills")
  requireValid(exitOpenReachable, "exit-reachability")
  requireValid(#level.gates >= (config.gates or 2), "gates")
  requireValid(gateReachable == #level.gates, "gate-reachability")
  requireValid(gateUsable == #level.gates, "gate-usability")
  requireValid(#level.locks >= (config.locks or 0), "locks")
  requireValid(level.exitKey ~= nil, "exit-key")
  requireValid(#level.keys >= max(1, config.keys or 1), "keys")
  requireValid(keyReachable == #level.keys, "key-reachability")
  requireValid(lockReachable == #level.locks, "lock-reachability")
  requireValid(lockUsable == #level.locks, "lock-usability")
  requireValid(#level.hazards >= max(0, (config.hazards or 0) - 2), "hazards")
  requireValid(#level.creatureSpawns >= 3, "creature-spawns")
  requireValid(#(level.npcSpawns or {}) >= 1, "npc-spawns")
  requireValid(#level.districts >= 4, "districts")
  requireValid(districtKinds >= 4, "district-kinds")
  requireValid(#level.nests >= 2, "nests")
  requireValid(#level.signals >= #level.nests + 1, "signals")
  requireValid(level.biomeProfile ~= nil, "biome-profile")
  requireValid(#(level.factions or {}) >= 2, "factions")
  requireValid(#(level.cycleShelters or {}) >= 1, "cycle-shelters")
  requireValid(#(level.roomModifiers or {}) >= 2, "room-modifiers")
  requireValid(level.stairCount == 0, "no-stairs")
  requireValid(level.ladderCount >= 2, "ladders")
  requireValid(level.distinctFloorHeights == 1, "flat-floor")
  requireValid(level.heightTransitionCount == 0, "no-height-transitions")
  requireValid(level.steepTransitionCount == 0, "no-steep-transitions")
  requireValid(level.ceilingTransitionCount == 0, "no-ceiling-transitions")
  requireValid(farthest.distance >= 18, "farthest")

  level.validation = {
    valid = #failures == 0,
    failures = failures,
    reachable = lockedReachable,
    openCells = lockedOpenCells,
    unlockedReachable = unlockedReachable,
    unlockedOpenCells = unlockedOpenCells,
    keyReachable = keyReachable,
    terminalReachable = 0,
    liftTerminalReachable = false,
    exitReachable = exitOpenReachable,
    gateReachable = gateReachable,
    gateUsable = gateUsable,
    lockReachable = lockReachable,
    lockUsable = lockUsable,
    farthest = farthest.distance,
    rooms = #level.rooms,
    objectives = 0,
    refills = #level.refills,
    gates = #level.gates,
    keys = #level.keys,
    locks = #level.locks,
    hazards = #level.hazards,
    terminals = 0,
    exitKey = level.exitKey ~= nil and 1 or 0,
    creatureSpawns = #level.creatureSpawns,
    npcSpawns = #(level.npcSpawns or {}),
    districts = #level.districts,
    districtKinds = districtKinds,
    nests = #level.nests,
    signals = #level.signals,
    factions = #(level.factions or {}),
    cycleShelters = #(level.cycleShelters or {}),
    roomModifiers = #(level.roomModifiers or {}),
    biome = level.biomeProfile and level.biomeProfile.district or "none",
    stairs = level.stairCount,
    ladders = level.ladderCount,
    floorHeights = level.distinctFloorHeights,
    heightTransitions = level.heightTransitionCount,
    steepTransitions = level.steepTransitionCount,
    ceilingTransitions = level.ceilingTransitionCount,
  }

  return level.validation
end

local function validateLevel(level)
  return Level.validate(level).valid
end

local function deckConfig(deck, width, height, branch)
  local base = Level.deckConfigs[deck] or Level.deckConfigs[#Level.deckConfigs]
  branch = normalizeBranch(branch, deck)
  local biomeProfile = Level.biomeProfiles[branch.biome] or Level.biomeProfiles.cryo_vault
  local branchRoomBonus = branch.kind == "salvage" and 2 or (branch.kind == "conflict" and 1 or 0)
  local rooms = max(12, base.rooms + love.math.random(-2, 3) + branchRoomBonus)
  local profile = layoutProfiles[love.math.random(#layoutProfiles)]
  local themes = {
    { "archive", "observatory", "chamber" },
    { "cistern", "bridgeworks", "machine shaft" },
    { "lower foundry", "quarry", "overgrown court" },
    { "annex", "chamber", "archive" },
  }
  local theme = themes[love.math.random(#themes)]
  theme = Biomes.themes[branch.biome] or theme

  return {
    width = width or base.width,
    height = height or base.height,
    rooms = rooms,
    keys = base.keys or 2,
    objectives = 0,
    refills = max(5, base.refills + floor((rooms - base.rooms) / 2)),
    gates = base.gates,
    locks = base.locks,
    hazards = max(6, base.hazards + rooms - base.rooms + (branch.risk or 1) - 1),
    terminals = 0,
    profile = profile,
    theme = theme,
    branch = branch,
    biomeProfile = biomeProfile,
  }
end

local function templateWeight(config, template, route)
  local weight = route and 4 or 3

  for _, kind in ipairs(config.theme or {}) do
    if template.kind == kind then
      weight = weight + 5
    end
  end

  if template.kind == "annex" or template.kind == "chamber" then
    weight = weight + (route and -1 or 2)
  end
  if template.id:match("deadend") and route then
    weight = 1
  end

  return max(1, weight)
end

local function templateForConnector(level, connector, route)
  local candidates = {}
  local total = 0

  for _, template in ipairs(moduleTemplates) do
    if template.connectors[connector] then
      local weight = templateWeight(level.config or {}, template, route)
      total = total + weight
      candidates[#candidates + 1] = { template = template, limit = total }
    end
  end

  local roll = love.math.random() * total
  for _, candidate in ipairs(candidates) do
    if roll <= candidate.limit then
      return candidate.template
    end
  end

  return candidates[#candidates].template
end

local function randomConnector(room, avoid)
  local choices = {}

  for _, direction in ipairs(directions) do
    if room.connectors[direction.name] and direction.name ~= avoid then
      choices[#choices + 1] = direction
    end
  end

  if #choices == 0 then
    return directions[love.math.random(#directions)]
  end

  return choices[love.math.random(#choices)]
end

local function socketPoint(room, directionName)
  if directionName == "north" then
    return {
      U.clamp(room.cx + love.math.random(-2, 2), room.x + 2, room.x + room.width - 3),
      room.y,
    }
  elseif directionName == "south" then
    return {
      U.clamp(room.cx + love.math.random(-2, 2), room.x + 2, room.x + room.width - 3),
      room.y + room.height - 1,
    }
  elseif directionName == "east" then
    return {
      room.x + room.width - 1,
      U.clamp(room.cy + love.math.random(-2, 2), room.y + 2, room.y + room.height - 3),
    }
  end

  return {
    room.x,
    U.clamp(room.cy + love.math.random(-2, 2), room.y + 2, room.y + room.height - 3),
  }
end

local function connectorVertices(a, b, directionName, style)
  local direction = directionByName[directionName]
  local startPoint = socketPoint(a, directionName)
  local endPoint = socketPoint(b, direction.opposite)

  if style == "direct" then
    return { startPoint, endPoint }
  end

  if style == "dogleg" then
    local axis = love.math.random() < 0.5
    local midA
    local midB

    if axis then
      local midX = floor((startPoint[1] + endPoint[1]) / 2) + love.math.random(-3, 3)
      midA = { midX, startPoint[2] }
      midB = { midX, endPoint[2] }
    else
      local midY = floor((startPoint[2] + endPoint[2]) / 2) + love.math.random(-3, 3)
      midA = { startPoint[1], midY }
      midB = { endPoint[1], midY }
    end

    return { startPoint, midA, midB, endPoint }
  end

  local bend
  if love.math.random() < 0.5 then
    bend = { endPoint[1], startPoint[2] }
  else
    bend = { startPoint[1], endPoint[2] }
  end

  return { startPoint, bend, endPoint }
end

local function connectModules(level, a, b, directionName, zone, terrain)
  local profile = level.profile or layoutProfiles[1]
  local roll = love.math.random()
  local style = "corridor"

  if roll < profile.directChance then
    style = "direct"
  elseif roll < profile.directChance + profile.doglegChance then
    style = "dogleg"
  end

  return carvePolyline(level, connectorVertices(a, b, directionName, style), 1, zone or "connector", terrain or "stone")
end

local function modulePosition(anchor, direction, width, height)
  local profile = anchor.levelProfile or layoutProfiles[1]
  local gap = love.math.random(profile.gap[1], profile.gap[2])
  local jitter = love.math.random(-profile.jitter, profile.jitter)
  local cx = anchor.cx
  local cy = anchor.cy

  if direction.name == "east" then
    cx = anchor.cx + floor(anchor.width / 2) + floor(width / 2) + gap
    cy = anchor.cy + jitter
  elseif direction.name == "west" then
    cx = anchor.cx - floor(anchor.width / 2) - floor(width / 2) - gap
    cy = anchor.cy + jitter
  elseif direction.name == "south" then
    cx = anchor.cx + jitter
    cy = anchor.cy + floor(anchor.height / 2) + floor(height / 2) + gap
  else
    cx = anchor.cx + jitter
    cy = anchor.cy - floor(anchor.height / 2) - floor(height / 2) - gap
  end

  return floor(cx - width / 2), floor(cy - height / 2)
end

local function placeConnectedRoom(level, anchor, direction, route)
  if not anchor.connectors[direction.name] then
    return nil
  end

  for _ = 1, 20 do
    local template = templateForConnector(level, direction.opposite, route)
    local width = randomRange(template.width)
    local height = randomRange(template.height)
    local x, y = modulePosition(anchor, direction, width, height)
    local room = addRoomAt(level, x, y, width, height, template.kind, route, template)

    if room then
      room.levelProfile = level.profile
      connectModules(level, anchor, room, direction.name, "connector", "stone")
      return room
    end
  end

  return nil
end

local function addStartRoom(level)
  local template = moduleTemplates[1]
  local width = randomRange(template.width)
  local height = randomRange(template.height)
  local offset = min(7, floor(level.width * 0.08))
  local x = floor(level.width / 2 - width / 2) + love.math.random(-offset, offset)
  local y = floor(level.height / 2 - height / 2) + love.math.random(-offset, offset)
  local room = addRoomAt(level, x, y, width, height, template.kind, true, template)

  if room then
    room.levelProfile = level.profile
    level.start = { x = room.cx, y = room.cy }
  end

  return room
end

local function growCriticalPath(level, config)
  local current = addStartRoom(level)
  local profile = level.profile or layoutProfiles[1]
  local target = max(config.objectives + 3, floor(config.rooms * profile.routeRatio))
  local lastDirection = nil
  local attempts = 0

  while current and #level.routeRooms < target and attempts < 360 do
    local direction = randomConnector(current, lastDirection and directionByName[lastDirection].opposite)
    local room = placeConnectedRoom(level, current, direction, true)

    if room then
      current = room
      lastDirection = direction.name
    else
      current = level.routeRooms[love.math.random(#level.routeRooms)]
      lastDirection = nil
      attempts = attempts + 1
    end
  end
end

local function fillSideRooms(level, config)
  local attempts = 0
  local profile = level.profile or layoutProfiles[1]

  while #level.rooms < config.rooms and attempts < 700 do
    local pool = love.math.random() < profile.sideRouteBias and level.routeRooms or level.rooms
    local anchor = pool[love.math.random(#pool)]
    local direction = randomConnector(anchor)
    local room = placeConnectedRoom(level, anchor, direction, false)

    if not room then
      attempts = attempts + 1
    end
  end
end

local function inferredDirection(a, b)
  local dx = b.cx - a.cx
  local dy = b.cy - a.cy

  if abs(dx) > abs(dy) then
    return dx > 0 and "east" or "west"
  end

  return dy > 0 and "south" or "north"
end

local function connectRoomPair(level, a, b, zone)
  local directionName = inferredDirection(a, b)
  local direction = directionByName[directionName]

  if a.connectors[directionName] and b.connectors[direction.opposite] then
    return connectModules(level, a, b, directionName, zone or "shortcut", "stone")
  end

  return connectRooms(level, a, b, 1, zone or "shortcut", "stone")
end

local function addShortcutMarkers(level, count, marker)
  local made = 0
  local attempts = 0

  while made < count and attempts < 120 do
    local a = level.rooms[love.math.random(#level.rooms)]
    local b = level.rooms[love.math.random(#level.rooms)]

    if a ~= b and abs(a.cx - b.cx) + abs(a.cy - b.cy) >= 12 then
      local before = marker == "gate" and #level.gates or #level.locks
      local points = connectRoomPair(level, a, b, marker == "gate" and "shortcut" or "locked shortcut")

      if marker == "gate" then
        markShortcutGate(level, points, made + 1)
        if #level.gates > before then
          made = made + 1
        end
      else
        markLock(level, points, made + 1)
        if #level.locks > before then
          made = made + 1
        end
      end
    end

    attempts = attempts + 1
  end
end

local function addOpenCrossLinks(level, count)
  local made = 0
  local attempts = 0

  while made < count and attempts < 120 do
    local a = level.rooms[love.math.random(#level.rooms)]
    local b = level.rooms[love.math.random(#level.rooms)]

    if a ~= b and abs(a.cx - b.cx) + abs(a.cy - b.cy) >= 14 then
      connectRoomPair(level, a, b, "crosslink")
      made = made + 1
    end

    attempts = attempts + 1
  end
end

local function placeObjectives(level, config)
  local lastRouteIndex = max(2, #level.routeRooms - 1)
  local used = {}

  for id = 1, config.objectives do
    local span = max(1, lastRouteIndex - 1)
    local index = 1 + floor(id * span / (config.objectives + 1))

    index = U.clamp(index + 1, 2, lastRouteIndex)
    while used[index] and index < lastRouteIndex do
      index = index + 1
    end
    used[index] = true
    markObjective(level, level.routeRooms[index], id)
  end
end

local function placeKeys(level, config)
  local lastRouteIndex = max(2, #level.routeRooms - 1)
  local exitIndex = U.clamp(floor(#level.routeRooms * 0.62), 2, lastRouteIndex)

  if not markKey(level, level.routeRooms[exitIndex], 1, "exit") then
    markKey(level, level.routeRooms[max(2, lastRouteIndex)], 1, "exit")
  end

  local smallKeys = max(config.locks or 0, (config.keys or 2) - 1)
  for id = 1, smallKeys do
    local index = U.clamp(floor(#level.routeRooms * (0.22 + id * 0.16)), 2, lastRouteIndex)
    if not markKey(level, level.routeRooms[index], id, "small") then
      markKey(level, level.routeRooms[1], id, "small")
    end
  end
end

local function placeRefills(level, config)
  local refillBudget = config.refills or 7

  for i = #level.rooms, 1, -1 do
    local room = level.rooms[i]
    if refillBudget > 0 and (not room.route or love.math.random() < 0.25) and markRefill(level, room) then
      refillBudget = refillBudget - 1
    end
  end
end

local function placeHazards(level, config)
  local hazardBudget = config.hazards or 0
  local attempts = 0

  while #level.hazards < hazardBudget and attempts < hazardBudget * 16 + 32 do
    local room = level.rooms[love.math.random(#level.rooms)]
    if room ~= level.routeRooms[1] and room ~= level.routeRooms[#level.routeRooms] then
      markHazard(level, room, #level.hazards + 1)
    end
    attempts = attempts + 1
  end
end

local function chooseRoomForDistrict(level, preferredKinds, fallbackIndex)
  for _, kind in ipairs(preferredKinds or {}) do
    for _, room in ipairs(level.rooms) do
      if room.kind == kind and not room.district then
        return room
      end
    end
  end

  for _, room in ipairs(level.rooms) do
    if not room.district and room ~= level.routeRooms[1] then
      return room
    end
  end

  return level.rooms[fallbackIndex or 1]
end

local function carveCaveDistrict(level, room)
  local district = addDistrict(level, "collapsed_caves", room, "rubble")
  if not district then
    return
  end

  local x, y = room.cx, room.cy
  for _ = 1, 82 + (level.deck or 1) * 12 do
    carveBrush(level, x, y, love.math.random() < 0.28 and 2 or 1, "quarry", 0.5, "rubble", "collapsed caves")
    tagCell(level, x, y, "rubble")
    tagCell(level, x, y, "dark")
    local direction = directions[love.math.random(#directions)]
    x = U.clamp(x + direction.dx * love.math.random(1, 3), room.x - 5, room.x + room.width + 4)
    y = U.clamp(y + direction.dy * love.math.random(1, 3), room.y - 5, room.y + room.height + 4)
  end
  addLevelSignal(level, room.cx, room.cy, "scratch", 1.2, "collapsed_caves")
end

local function carveFloodedBasin(level, room)
  local district = addDistrict(level, "flooded_basin", room, "water")
  if not district then
    return
  end

  local radius = max(4, floor(min(room.width, room.height) * 0.45))
  for y = room.cy - radius, room.cy + radius do
    for x = room.cx - radius, room.cx + radius do
      local distance = sqrt((x - room.cx) ^ 2 + (y - room.cy) ^ 2)
      if distance <= radius + love.math.random() * 1.6 then
        carveCell(level, x, y, "cistern", 0.48, "water", "flooded basin")
        tagCell(level, x, y, "water")
        tagCell(level, x, y, "flooded")
        if love.math.random() < 0.12 then
          local cell = tagCell(level, x, y, "wire")
          if cell and not cell.hazard then
            cell.hazard = { id = #level.hazards + 1, kind = "wire", active = true, suppressed = false }
            cell.kind = "wire"
            cell.terrain = "grate"
            level.hazards[#level.hazards + 1] = { x = x, y = y, cell = cell, id = cell.hazard.id, kind = "wire", room = room }
          end
        end
      end
    end
  end
  addLevelSignal(level, room.cx, room.cy, "wet_tracks", 1.2, "flooded_basin")
end

local function carveMachineMaze(level, room)
  local district = addDistrict(level, "machine_maze", room, "machine")
  if not district then
    return
  end

  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      local cell = Level.cellAtCell(level, x, y)
      if cell and not cell.solid then
        cell.district = "machine_maze"
        cell.tags = cell.tags or {}
        cell.tags.machine = true
        if (x + y) % 5 == 0 then
          setSolidFeature(level, x, y, "machinery", 0.34)
        elseif x % 3 == 0 or y % 4 == 0 then
          setTerrain(level, x, y, "grate", 0.66, "service deck", "machine maze")
          if love.math.random() < 0.08 then
            local ventCell = Level.cellAtCell(level, x, y)
            if ventCell then
              ventCell.vent = true
              ventCell.kind = "vent"
              ventCell.landmark = "vent"
              ventCell.tags = ventCell.tags or {}
              ventCell.tags.vent = true
            end
          end
        end
      end
    end
  end

  restoreRoomCenter(level, room)
  addLevelSignal(level, room.cx, room.cy, "vent_call", 1.1, "machine_maze")
end

local function carveFoundryArena(level, room)
  local district = addDistrict(level, "foundry_arena", room, "arena")
  if not district then
    return
  end

  local radius = min(room.width, room.height) * 0.42
  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      local distance = sqrt((x - room.cx) ^ 2 + (y - room.cy) ^ 2)
      local cell = Level.cellAtCell(level, x, y)
      if cell and not cell.solid then
        cell.district = "foundry_arena"
        cell.tags = cell.tags or {}
        cell.tags.arena = true
        if distance < radius then
          setTerrain(level, x, y, "catwalk", 0.68, "catwalk", "foundry arena")
        elseif love.math.random() < 0.28 then
          setTerrain(level, x, y, "slag", 0.72, "ember", "foundry arena")
        end
      end
    end
  end
  addLevelSignal(level, room.cx, room.cy, "ash_drift", 1.1, "foundry_arena")
end

local function placeHybridDistricts(level)
  if level.routeRooms[1] then
    addDistrict(level, "atrium_spine", level.routeRooms[1], "start")
  end
  if level.routeRooms[#level.routeRooms] then
    addDistrict(level, "escape_shaft", level.routeRooms[#level.routeRooms], "exit")
  end

  carveCaveDistrict(level, chooseRoomForDistrict(level, { "quarry", "annex", "chamber" }, 2))
  carveFloodedBasin(level, chooseRoomForDistrict(level, { "cistern", "observatory" }, 3))
  carveMachineMaze(level, chooseRoomForDistrict(level, { "machine shaft", "bridgeworks" }, 4))
  carveFoundryArena(level, chooseRoomForDistrict(level, { "lower foundry", "bridgeworks" }, 5))

  local salvage = chooseRoomForDistrict(level, { "archive", "annex", "chamber" }, 6)
  if salvage then
    addDistrict(level, "salvage_vault", salvage, "salvage")
  end
end

local function markBiomeHazard(level, room, kind)
  for _ = 1, 18 do
    local x = love.math.random(room.x + 1, room.x + room.width - 2)
    local y = love.math.random(room.y + 1, room.y + room.height - 2)
    local cell = Level.cellAtCell(level, x, y)
    if cell and not cell.solid and not preserveRoomSpine(room, x, y) and not cell.objective and not cell.gate and not cell.ladder and not cell.refill and not cell.key and not cell.terminal and not cell.exit and not cell.hazard then
      cell.hazard = { id = #level.hazards + 1, kind = kind, active = true, suppressed = false, biome = level.biomeProfile and level.biomeProfile.district }
      if kind == "ember" then
        cell.terrain = "reactor"
        cell.light = max(cell.light or 0.5, 0.82)
      elseif kind == "wire" then
        cell.terrain = "grate"
        cell.light = max(cell.light or 0.5, 0.7)
      else
        cell.terrain = "rubble"
        cell.light = min(cell.light or 0.5, 0.42)
      end
      cell.kind = kind
      level.hazards[#level.hazards + 1] = { x = x, y = y, cell = cell, id = cell.hazard.id, kind = kind, room = room }
      return true
    end
  end

  return false
end

local markCycleShelter

local function paintBiomeRoom(level, room, profile)
  if not room or not profile then
    return
  end

  addDistrict(level, profile.district, room, "biome")
  room.biome = profile.district
  room.factionSeed = profile.primaryFaction

  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      local cell = Level.cellAtCell(level, x, y)
      if cell and not cell.solid and not cell.objective and not cell.exit and not cell.ladder then
        local distance = abs(x - room.cx) + abs(y - room.cy)
        if distance % 3 ~= 0 or love.math.random() < 0.42 then
          setTerrain(level, x, y, profile.terrain, max(cell.light or 0.5, 0.54), profile.district, profile.label:lower())
          cell.biome = profile.district
          cell.tags = cell.tags or {}
          cell.tags[profile.district] = true
        end
      end
    end
  end

  if profile.district == "cryo_vault" then
    for _ = 1, 2 do
      markBiomeHazard(level, room, "pit")
    end
  elseif profile.district == "fungal_service" then
    addLevelSignal(level, room.cx, room.cy, "spore_bloom", 1.4, "fungal_service")
  elseif profile.district == "pressure_lab" then
    markBiomeHazard(level, room, "wire")
    if love.math.random() < 0.7 then
      markVent(level, room)
    end
  elseif profile.district == "reactor_trench" then
    for _ = 1, 3 do
      markBiomeHazard(level, room, "ember")
    end
  elseif profile.district == "waste_artery" then
    for _ = 1, 2 do
      markBiomeHazard(level, room, "wire")
    end
  elseif profile.district == "storm_drain" then
    for _ = 1, 3 do
      markBiomeHazard(level, room, "wire")
    end
    markCycleShelter(level, room, "storm")
  elseif profile.district == "ash_foundry" then
    for _ = 1, 3 do
      markBiomeHazard(level, room, "ember")
    end
    addLevelSignal(level, room.cx, room.cy, "smoke_veil", 1.25, "ash_foundry")
  elseif profile.district == "signal_catacombs" then
    markBiomeHazard(level, room, "wire")
    addLevelSignal(level, room.cx, room.cy, "false_ping", 1.6, "signal_catacombs")
  elseif profile.district == "bone_market" then
    markBiomeHazard(level, room, "pit")
    addLevelSignal(level, room.cx, room.cy, "trade_mark", 1.4, "bone_market")
  elseif profile.district == "organ_machine" then
    markBiomeHazard(level, room, "wire")
    markCycleShelter(level, room, "organ")
    addLevelSignal(level, room.cx, room.cy, "pulse_mark", 1.35, "organ_machine")
  end

  addLevelSignal(level, room.cx, room.cy, profile.signal, 1.35, profile.district)
end

local function placeBiomeDistricts(level)
  local profile = level.biomeProfile
  if not profile then
    return
  end

  local target = min(4, max(2, 1 + (level.branch and level.branch.risk or 1)))
  local painted = 0
  local first = chooseRoomForDistrict(level, { "annex", "chamber", "archive" }, 3)
  if first then
    paintBiomeRoom(level, first, profile)
    painted = painted + 1
  end

  for i = #level.rooms, 1, -1 do
    if painted >= target then
      break
    end
    local room = level.rooms[i]
    if not room.route and not room.biome and room ~= level.routeRooms[1] and room ~= level.routeRooms[#level.routeRooms] then
      paintBiomeRoom(level, room, profile)
      painted = painted + 1
    end
  end

  level.ecologyEvents[#level.ecologyEvents + 1] = {
    kind = "biome",
    biome = profile.district,
    faction = level.branch and level.branch.faction or profile.primaryFaction,
  }
end

function markCycleShelter(level, room, reason)
  if not room then
    return false
  end

  local cell = Level.cellAtCell(level, room.cx, room.cy)
  if not cell or Level.isBlocked(cell) then
    return false
  end

  room.shelter = true
  room.shelterReason = reason or "cycle"
  cell.shelter = true
  cell.kind = "shelter"
  cell.landmark = "shelter"
  cell.light = max(cell.light or 0.5, 0.86)
  cell.tags = cell.tags or {}
  cell.tags.shelter = true
  if cell.terrain == "water" or cell.terrain == "storm" then
    cell.terrain = "catwalk"
  elseif cell.terrain == "slag" or cell.terrain == "reactor" then
    cell.terrain = "grate"
  end

  level.cycleShelters[#level.cycleShelters + 1] = { x = room.cx, y = room.cy, room = room, reason = reason or "cycle", cell = cell }
  addLevelSignal(level, room.cx, room.cy, "shelter_mark", 1.1, reason or "cycle")
  return true
end

local function paintRoomModifier(level, room, modifierName, modifier)
  if not room or not modifier then
    return
  end

  room.modifier = modifierName
  level.roomModifiers[#level.roomModifiers + 1] = { room = room, kind = modifierName }

  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      local cell = Level.cellAtCell(level, x, y)
      if cell and not cell.solid and not cell.objective and not cell.exit and not cell.ladder and love.math.random() < 0.34 then
        setTerrain(level, x, y, modifier.terrain or cell.terrain, modifier.light and max(cell.light or 0.5, modifier.light) or cell.light, room.kind, room.zone)
        cell.modifier = modifierName
        cell.tags = cell.tags or {}
        cell.tags[modifierName] = true
      end
    end
  end

  if modifier.signal then
    addLevelSignal(level, room.cx, room.cy, modifier.signal, 1.05 + (level.branch and level.branch.risk or 1) * 0.08, modifierName)
  end
  if modifier.hazard and love.math.random() < 0.84 then
    markBiomeHazard(level, room, modifier.hazard)
  end
  if modifier.shelter then
    markCycleShelter(level, room, modifierName)
  end
end

local function placeRoomModifiers(level)
  local order = Level.roomModifierOrder or {}
  local target = min(5, max(2, 1 + (level.branch and level.branch.risk or 1)))
  local made = 0

  for i = #level.rooms, 1, -1 do
    if made >= target then
      break
    end
    local room = level.rooms[i]
    if room and not room.route and not room.modifier and room ~= level.routeRooms[1] and room ~= level.routeRooms[#level.routeRooms] then
      local index = ((level.deck or 1) + i + made) % #order + 1
      local name = order[index]
      paintRoomModifier(level, room, name, Level.roomModifiers and Level.roomModifiers[name])
      made = made + 1
    end
  end
end

local function placeCycleShelters(level)
  local target = max(1, min(3, 1 + floor((level.branch and level.branch.risk or 1) / 2)))
  local made = #level.cycleShelters

  for i = 2, max(2, #level.routeRooms - 1) do
    if made >= target then
      return
    end
    local room = level.routeRooms[i]
    if room and not room.shelter and i % 3 == 0 and markCycleShelter(level, room, "route") then
      made = made + 1
    end
  end

  for _, room in ipairs(level.rooms or {}) do
    if made >= target then
      return
    end
    if not room.shelter and not room.route and markCycleShelter(level, room, "side") then
      made = made + 1
    end
  end
end

local function placeVents(level)
  local target = min(4, max(2, floor(#level.rooms / 6)))
  local made = 0

  for i = #level.rooms, 1, -1 do
    if made >= target then
      return
    end
    local room = level.rooms[i]
    if (room.kind == "machine shaft" or room.kind == "bridgeworks" or room.kind == "lower foundry" or not room.route) and markVent(level, room) then
      made = made + 1
    end
  end
end

local function placeSalvageRooms(level)
  local tools = { "flare", "noisemaker", "scent", "snare", "pheromone", "probe", "oil", "beacon" }
  if level.biomeProfile and level.biomeProfile.salvageTools then
    tools = level.biomeProfile.salvageTools
  end
  local salvageBonus = level.branch and level.branch.kind == "salvage" and 1 or 0
  local target = min(4, max(1, floor(#level.rooms / 7) + salvageBonus))
  local made = 0

  for i = #level.rooms, 1, -1 do
    if made >= target then
      break
    end

    local room = level.rooms[i]
    if not room.route and room ~= level.routeRooms[1] and room ~= level.routeRooms[#level.routeRooms] then
      room.salvage = true
      level.salvageRooms[#level.salvageRooms + 1] = room
      for y = room.y + 1, room.y + room.height - 2 do
        for x = room.x + 1, room.x + room.width - 2 do
          local cell = Level.cellAtCell(level, x, y)
          if cell and not cell.solid then
            cell.salvage = true
          end
        end
      end
      markToolCache(level, room, tools[((made * 2) % #tools) + 1], made + 1)
      if love.math.random() < 0.62 then
        markToolCache(level, room, tools[((made * 2 + 1) % #tools) + 1], made + 10)
      end
      if level.branch and level.branch.kind == "salvage" and (level.branch.rareCache or love.math.random() < 0.58) then
        markToolCache(level, room, tools[((made * 3 + 2) % #tools) + 1], made + 20)
      end
      made = made + 1
    end
  end
end

local function addNest(level, kind, room)
  if not room then
    return nil
  end

  local cell = Level.cellAtCell(level, room.cx, room.cy)
  if not cell or Level.isBlocked(cell) then
    return nil
  end

  addDistrict(level, "nest_zone", room, "nest")
  room.role = "nest"
  room.nestKind = kind
  cell.kind = kind .. " nest"
  cell.landmark = "nest"
  cell.light = max(cell.light or 0.5, 0.7)
  cell.tags = cell.tags or {}
  cell.tags.nest = true
  cell.tags[kind .. "_nest"] = true

  local nest = {
    id = #level.nests + 1,
    kind = kind,
    x = room.cx,
    y = room.cy,
    room = room,
    hoard = {},
    alarm = 0,
    raidTimer = love.math.random() * 8,
  }

  level.nests[#level.nests + 1] = nest
  addLevelSignal(level, room.cx, room.cy, "nest_debris", 1.3, kind)
  return nest
end

local function placeNests(level)
  local specs = {
    { kind = "skitter", rooms = { "salvage_vault", "archive", "annex" } },
    { kind = "stalker", rooms = { "collapsed_caves", "archive", "annex" } },
    { kind = "screecher", rooms = { "machine_maze", "machine shaft", "bridgeworks" } },
    { kind = "burrower", rooms = { "flooded_basin", "collapsed_caves", "cistern", "quarry" } },
    { kind = "hunter", rooms = { "foundry_arena", "escape_shaft", "quarry" } },
  }

  for i, spec in ipairs(specs) do
    if i <= 2 + (level.deck or 1) then
      local room
      for _, districtKind in ipairs(spec.rooms) do
        for _, candidate in ipairs(level.rooms) do
          if not candidate.nestKind and (candidate.district == districtKind or candidate.kind == districtKind or candidate.role == districtKind) then
            room = candidate
            break
          end
        end
        if room then
          break
        end
      end
      room = room or chooseRoomForDistrict(level, {}, 1 + i)
      addNest(level, spec.kind, room)
    end
  end
end

local function placeFactions(level)
  local profile = level.biomeProfile or Level.biomeProfiles.cryo_vault
  local names = profile.factions or { profile.primaryFaction or "scavenger", "predator" }
  level.factions = {}

  for i, name in ipairs(names) do
    level.factions[#level.factions + 1] = {
      id = i,
      name = name,
      territory = 0,
      alarm = 0,
      greed = 0.35 + love.math.random() * 0.55,
      fear = 0.15 + love.math.random() * 0.45,
      hostility = {},
    }
  end

  for i, faction in ipairs(level.factions) do
    for j, other in ipairs(level.factions) do
      if i ~= j then
        faction.hostility[other.name] = (level.branch and level.branch.kind == "conflict") and 0.92 or 0.55
      end
    end
  end

  for i, nest in ipairs(level.nests or {}) do
    local faction = level.factions[((i - 1) % max(1, #level.factions)) + 1]
    nest.faction = faction.name
    nest.alarm = max(nest.alarm or 0, faction.alarm or 0)
    if nest.room then
      nest.room.faction = faction.name
      faction.territory = faction.territory + 1
    end
  end

  for _, room in ipairs(level.rooms or {}) do
    if room.biome and not room.faction and #level.factions > 0 then
      local faction = level.factions[love.math.random(#level.factions)]
      room.faction = faction.name
      faction.territory = faction.territory + 1
    end

    if room.faction then
      for y = room.y, room.y + room.height - 1 do
        for x = room.x, room.x + room.width - 1 do
          local cell = Level.cellAtCell(level, x, y)
          if cell and not cell.solid then
            cell.faction = room.faction
          end
        end
      end
    end
  end
end

local function addCreatureSpawn(level, kind, room, nest)
  if not room then
    return false
  end

  local cell = Level.cellAtCell(level, room.cx, room.cy)
  if cell and not Level.isBlocked(cell) then
    level.creatureSpawns[#level.creatureSpawns + 1] = {
      kind = kind,
      x = room.cx,
      y = room.cy,
      room = room,
      nest = nest,
      faction = (nest and nest.faction) or room.faction,
    }
    return true
  end

  return false
end

local function placeCreatureSpawns(level)
  local farthest = Level.farthestCellFrom(level, level.start.x, level.start.y)
  local farRoom = level.routeRooms[#level.routeRooms]
  addCreatureSpawn(level, "hunter", farRoom or { cx = farthest.x, cy = farthest.y })

  for _, nest in ipairs(level.nests or {}) do
    addCreatureSpawn(level, nest.kind, nest.room, nest)
  end

  for _, room in ipairs(level.rooms) do
    if not room.route and #level.creatureSpawns < 7 then
      if room.kind == "archive" or room.kind == "annex" then
        addCreatureSpawn(level, "stalker", room)
      elseif room.kind == "cistern" or room.kind == "quarry" then
        addCreatureSpawn(level, "burrower", room)
      elseif room.kind == "machine shaft" or room.kind == "bridgeworks" then
        addCreatureSpawn(level, "screecher", room)
      else
        addCreatureSpawn(level, "skitter", room)
      end
    end
  end

  local biome = level.biomeProfile and level.biomeProfile.district
  local biomeSpawns = CreatureContent.biomeSpawns[biome] or {}
  for i, kind in ipairs(biomeSpawns) do
    if #level.creatureSpawns >= 9 then
      break
    end
    local room = level.salvageRooms[i] or level.routeRooms[max(2, #level.routeRooms - i)] or level.rooms[((i * 3) % #level.rooms) + 1]
    addCreatureSpawn(level, kind, room)
  end
end

local function placeOpeningSignals(level)
  local kinds = { "scratch", "wet_tracks", "vent_call", "ash_drift", "dark_pulse" }
  local kind = kinds[((level.deck or 1) - 1) % #kinds + 1]
  addLevelSignal(level, level.start.x, level.start.y, kind, 1.4, "opening")

  local firstNest = level.nests and level.nests[1]
  if firstNest then
    local dx = firstNest.x > level.start.x and 1 or -1
    local dy = firstNest.y > level.start.y and 1 or -1
    addLevelSignal(level, U.clamp(level.start.x + dx * 2, 2, level.width - 1), U.clamp(level.start.y + dy * 2, 2, level.height - 1), "nest_debris", 1.1, firstNest.kind)
  end
end

local function placeLandmarks(level)
  local placed = 0

  for i = #level.rooms, 1, -1 do
    local room = level.rooms[i]
    if not room.route and markLadder(level, room) then
      placed = placed + 1
      if placed >= 2 then
        return
      end
    end
  end

  for i = 2, #level.routeRooms - 1 do
    if placed >= 2 then
      return
    end
    if markLadder(level, level.routeRooms[i]) then
      placed = placed + 1
    end
  end
end

local function placeDynamicRooms(level)
  local marked = 0

  for i = #level.rooms, 1, -1 do
    local room = level.rooms[i]
    if not room.route and marked < 3 then
      markDynamicCells(level, room)
      marked = marked + 1
    end
  end
end

local function unlockTarget(level)
  if #level.gates > 0 then
    return { type = "gate", index = love.math.random(#level.gates) }
  end
  if #level.locks > 0 then
    return { type = "lock", index = love.math.random(#level.locks) }
  end
  return nil
end

local function hazardRoom(level)
  if #level.hazards > 0 then
    local hazard = level.hazards[love.math.random(#level.hazards)]
    if hazard.room then
      return hazard.room
    end
  end

  return level.rooms[love.math.random(#level.rooms)]
end

local function terminalRoomForCommand(level, command)
  if command == "SCAN" then
    return level.routeRooms[min(2, #level.routeRooms)] or level.rooms[1]
  elseif command == "LIFT" then
    return level.routeRooms[max(2, #level.routeRooms - 1)] or level.rooms[#level.rooms]
  elseif command == "PURGE" then
    return hazardRoom(level)
  end

  return level.rooms[love.math.random(#level.rooms)]
end

local function terminalTarget(level, command)
  if command == "UNLOCK" then
    return unlockTarget(level)
  end
  return nil
end

local function terminalRoles(level, config)
  if level.deck == 1 then
    return { "SCAN", "UNLOCK" }
  elseif level.deck == 2 then
    return { "SCAN", "PURGE", "LIFT" }
  end

  return { "SCAN", "UNLOCK", "PURGE", "LIFT" }
end

local function placeTerminalAnywhere(level, id, command)
  for _ = 1, 24 do
    local room = terminalRoomForCommand(level, command)
    if room and markTerminal(level, room, id, command, terminalTarget(level, command)) then
      return true
    end
  end

  for _, room in ipairs(level.rooms) do
    if markTerminal(level, room, id, command, terminalTarget(level, command)) then
      return true
    end
  end

  return false
end

local function placeTerminals(level, config)
  local roles = terminalRoles(level, config)
  local target = config.terminals or #roles

  for i = 1, min(target, #roles) do
    placeTerminalAnywhere(level, i, roles[i])
  end

  while #level.terminals < target do
    local command = terminalCommands[love.math.random(#terminalCommands - 1)]
    if not placeTerminalAnywhere(level, #level.terminals + 1, command) then
      return
    end
  end
end

local function npcSpawnClear(level, x, y, visited)
  local cell = Level.cellAtCell(level, x, y)

  if not cell or cell.solid or not visited[U.keyOf(x, y)] then
    return false
  end

  if cell.objective or cell.gate or cell.ladder or cell.refill or cell.key or cell.lock or cell.hazard or cell.terminal or cell.exit or cell.tool or cell.vent then
    return false
  end

  for _, spawn in ipairs(level.npcSpawns or {}) do
    local dx = spawn.x - x
    local dy = spawn.y - y
    if dx * dx + dy * dy < 16 then
      return false
    end
  end

  return true
end

local function markNPCSpawn(level, room, id, visited)
  if not room then
    return false
  end

  for _ = 1, 22 do
    local x = U.clamp(room.cx + love.math.random(-4, 4), room.x + 1, room.x + room.width - 2)
    local y = U.clamp(room.cy + love.math.random(-4, 4), room.y + 1, room.y + room.height - 2)

    if npcSpawnClear(level, x, y, visited) then
      local kind = NPCContent.order[((level.deck or 1) + id - 2) % #NPCContent.order + 1]
      level.npcSpawns[#level.npcSpawns + 1] = {
        x = x,
        y = y,
        id = id,
        kind = kind,
        room = room,
      }
      return true
    end
  end

  return false
end

local function addRoomCandidate(candidates, room, seen)
  if not room or seen[room] then
    return
  end
  seen[room] = true
  candidates[#candidates + 1] = room
end

local function placeNPCs(level)
  local target = (level.deck or 1) >= 2 and 2 or 1
  local _, visited = Level.farthestCellFrom(level, level.start.x, level.start.y)
  local candidates = {}
  local seen = {}

  for _, shelter in ipairs(level.cycleShelters or {}) do
    addRoomCandidate(candidates, shelter.room, seen)
  end
  addRoomCandidate(candidates, level.routeRooms[2], seen)
  addRoomCandidate(candidates, level.routeRooms[max(1, #level.routeRooms - 1)], seen)
  addRoomCandidate(candidates, level.rooms[1], seen)

  for _, room in ipairs(level.rooms or {}) do
    addRoomCandidate(candidates, room, seen)
  end

  for _, room in ipairs(candidates) do
    if #level.npcSpawns >= target then
      return
    end
    markNPCSpawn(level, room, #level.npcSpawns + 1, visited)
  end
end

local function finalizeGeneratedLevel(level, config)
  for _, room in ipairs(level.rooms) do
    mutateRoomShape(level, room)
  end

  for _, room in ipairs(level.rooms) do
    decorateRoom(level, room)
  end

  addColumns(level)
  placeHybridDistricts(level)
  markExit(level, level.routeRooms[#level.routeRooms])
  placeKeys(level, config)
  addOpenCrossLinks(level, (level.profile and level.profile.openLinks or 0) + love.math.random(0, 1))
  addShortcutMarkers(level, config.gates or 2, "gate")
  addShortcutMarkers(level, config.locks or 0, "lock")
  placeLandmarks(level)
  placeHazards(level, config)
  placeBiomeDistricts(level)
  placeRoomModifiers(level)
  placeCycleShelters(level)
  placeVents(level)
  placeRefills(level, config)
  placeSalvageRooms(level)
  placeNests(level)
  placeFactions(level)
  placeOpeningSignals(level)
  placeCreatureSpawns(level)

  local startCell = Level.cellAtCell(level, level.start.x, level.start.y)
  if startCell then
    carveCell(level, level.start.x, level.start.y, "atrium", 0.82, "flagstone", "atrium")
  end

  sealUnreachableCells(level)
  placeNPCs(level)
  return level
end

local function generateMegastructure(width, height, deck, branch)
  local config = deckConfig(deck or 1, width, height, branch)
  local level = makeLevel(config.width, config.height, deck or 1, config)

  growCriticalPath(level, config)
  fillSideRooms(level, config)
  if #level.routeRooms == 0 or #level.rooms < config.rooms then
    return level
  end

  return finalizeGeneratedLevel(level, config)
end

function Level.generate(width, height, deck, branch)
  local last
  deck = deck or 1

  for _ = 1, 14 do
    local level = generateMegastructure(width, height, deck, branch)
    last = level
    if validateLevel(level) then
      return level
    end
  end

  validateLevel(last)
  return last
end

return Level
