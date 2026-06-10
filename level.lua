local U = require("utils")

local floor = math.floor
local abs = math.abs
local min = math.min
local max = math.max
local sqrt = math.sqrt

local Level = {
  width = 57,
  height = 57,
  maxStepHeight = 0.58,
  floorHeight = 0,
  ceilingHeight = 3.05,
}

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
  ladder = "LADDER",
}

local objectiveLabels = {
  "NORTH RELAY",
  "EAST RELAY",
  "SOUTH RELAY",
  "WEST RELAY",
}

local metricNeighbors = {
  { 1, 0 },
  { 0, 1 },
}

local function zoneStyle(kind)
  return zoneStyles[kind] or zoneStyles.chamber
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
    landmark = nil,
  }
end

local function makeLevel(width, height)
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
    grid = grid,
    rooms = {},
    routeRooms = {},
    start = { x = floor(width / 2), y = floor(height / 2) },
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
    gates = {},
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
  return cell == nil or cell.solid or cell.gateLocked
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
  }

  level.rooms[#level.rooms + 1] = room
  if route then
    level.routeRooms[#level.routeRooms + 1] = room
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
  cell.landmark = nil
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

    if cell and not cell.solid and not cell.objective and not cell.gate and not cell.ladder and not cell.refill then
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

local function findGatePoint(level, points)
  local mid = floor(#points / 2)

  for offset = 0, mid do
    for _, index in ipairs({ mid - offset, mid + offset }) do
      local point = points[index]
      if point then
        local cell = Level.cellAtCell(level, point[1], point[2])
        if cell and not cell.solid and not cell.objective and not cell.refill and not cell.ladder then
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

function Level.setGatesLocked(level, locked)
  for _, gate in ipairs(level.gates or {}) do
    gate.cell.gateLocked = locked
  end
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

local function reachableFromStart(level, gatesLocked)
  local states = setGateState(level, gatesLocked)
  local farthest, visited = Level.farthestCellFrom(level, level.start.x, level.start.y)
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
    if (gate.required or math.huge) <= #level.objectives and gateDegree(level, gate) >= 2 then
      usable = usable + 1
    end
  end

  restoreGateState(level, states)
  return reachable, usable
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
  local _, visited = Level.farthestCellFrom(level, level.start.x, level.start.y)
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
        cell.landmark = nil
      end
    end
  end

  compactRefills(level)
end

function Level.validate(level)
  countFeatures(level)

  local lockedReachable, lockedVisited, farthest = reachableFromStart(level, true)
  local unlockedReachable, unlockedVisited = reachableFromStart(level, false)
  local lockedOpenCells = countOpenCells(level, false)
  local unlockedOpenCells = countOpenCells(level, true)
  local lockedConnected = countVisitedCells(level, lockedVisited, false)
  local unlockedConnected = countVisitedCells(level, unlockedVisited, true)
  local objectiveReachable = countReachableObjectives(level, lockedVisited)
  local atriumEscapeReachable = countReachableObjectives(level, unlockedVisited)
  local gateReachable, gateUsable = countUsableGates(level, unlockedVisited)
  local failures = {}

  local function requireValid(condition, label)
    if not condition then
      failures[#failures + 1] = label
    end
  end

  requireValid(lockedReachable >= 360, "min-reachable")
  requireValid(lockedConnected == lockedOpenCells, "locked-connectivity")
  requireValid(unlockedConnected == unlockedOpenCells, "unlocked-connectivity")
  requireValid(#level.rooms >= 12, "rooms")
  requireValid(#level.objectives >= 4, "objectives")
  requireValid(#level.refills >= 5, "refills")
  requireValid(objectiveReachable == #level.objectives, "objective-reachability")
  requireValid(atriumEscapeReachable == #level.objectives, "atrium-escape")
  requireValid(#level.gates >= 2, "gates")
  requireValid(gateReachable == #level.gates, "gate-reachability")
  requireValid(gateUsable == #level.gates, "gate-usability")
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
    objectiveReachable = objectiveReachable,
    atriumEscapeReachable = atriumEscapeReachable,
    gateReachable = gateReachable,
    gateUsable = gateUsable,
    farthest = farthest.distance,
    rooms = #level.rooms,
    objectives = #level.objectives,
    refills = #level.refills,
    gates = #level.gates,
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

local function placeObjectives(level)
  for i = 2, min(#level.routeRooms, 5) do
    markObjective(level, level.routeRooms[i], i - 1)
  end
end

local function placeRefills(level)
  local refillBudget = 7

  for i = #level.rooms, 1, -1 do
    local room = level.rooms[i]
    if not room.route and refillBudget > 0 and markRefill(level, room) then
      refillBudget = refillBudget - 1
    end
  end
end

local function buildShortcutGates(level, nw, ne, se, sw)
  local eastX = U.clamp(min(ne.cx, se.cx) - 3, 4, level.width - 4)
  local westX = U.clamp(max(nw.cx, sw.cx) + 3, 4, level.width - 4)
  local eastPoints = carvePolyline(level, {
    { ne.cx, ne.cy },
    { eastX, ne.cy },
    { eastX, se.cy },
    { se.cx, se.cy },
  }, 1, "shortcut", "stone")
  local westPoints = carvePolyline(level, {
    { nw.cx, nw.cy },
    { westX, nw.cy },
    { westX, sw.cy },
    { sw.cx, sw.cy },
  }, 1, "shortcut", "stone")

  markShortcutGate(level, eastPoints, 2)
  markShortcutGate(level, westPoints, 3)
end

local function generateMegastructure(width, height)
  local level = makeLevel(width, height)
  local cx = floor(width / 2)
  local cy = floor(height / 2)
  local center = addJitteredRoom(level, cx, cy, { 13, 15 }, { 11, 13 }, "atrium", true)
  local north = addJitteredRoom(level, cx, cy - 18, { 10, 13 }, { 8, 10 }, "archive", true)
  local east = addJitteredRoom(level, cx + 18, cy, { 9, 11 }, { 10, 13 }, "machine shaft", true)
  local south = addJitteredRoom(level, cx, cy + 18, { 10, 13 }, { 8, 10 }, "cistern", true)
  local west = addJitteredRoom(level, cx - 18, cy, { 9, 11 }, { 10, 13 }, "observatory", true)

  level.start = { x = center.cx, y = center.cy }

  connectRooms(level, center, north, 1)
  connectRooms(level, center, east, 1)
  connectRooms(level, center, south, 1)
  connectRooms(level, center, west, 1)
  connectRooms(level, north, east, 1)
  connectRooms(level, east, south, 1)
  connectRooms(level, south, west, 1)
  connectRooms(level, west, north, 1)

  local nw = addJitteredRoom(level, cx - 15, cy - 15, { 7, 9 }, { 7, 9 }, "overgrown court", false)
  local ne = addJitteredRoom(level, cx + 15, cy - 15, { 7, 9 }, { 7, 9 }, "bridgeworks", false)
  local se = addJitteredRoom(level, cx + 15, cy + 15, { 7, 9 }, { 7, 9 }, "quarry", false)
  local sw = addJitteredRoom(level, cx - 15, cy + 15, { 7, 9 }, { 7, 9 }, "lower foundry", false)
  local innerNw = addJitteredRoom(level, cx - 8, cy - 8, { 6, 8 }, { 6, 8 }, "annex", false)
  local innerNe = addJitteredRoom(level, cx + 8, cy - 8, { 6, 8 }, { 6, 8 }, "chamber", false)
  local innerSe = addJitteredRoom(level, cx + 8, cy + 8, { 6, 8 }, { 6, 8 }, "annex", false)
  local innerSw = addJitteredRoom(level, cx - 8, cy + 8, { 6, 8 }, { 6, 8 }, "chamber", false)

  connectRooms(level, nw, north, 1)
  connectRooms(level, nw, west, 1)
  connectRooms(level, ne, north, 1)
  connectRooms(level, ne, east, 1)
  connectRooms(level, se, east, 1)
  connectRooms(level, se, south, 1)
  connectRooms(level, sw, south, 1)
  connectRooms(level, sw, west, 1)
  connectRooms(level, innerNw, center, 1)
  connectRooms(level, innerNe, center, 1)
  connectRooms(level, innerSe, center, 1)
  connectRooms(level, innerSw, center, 1)

  for _, room in ipairs(level.rooms) do
    decorateRoom(level, room)
  end

  addColumns(level)
  placeObjectives(level)
  buildShortcutGates(level, nw, ne, se, sw)
  markLadder(level, nw)
  markLadder(level, ne)
  markLadder(level, se)
  markLadder(level, sw)
  placeRefills(level)

  local startCell = Level.cellAtCell(level, level.start.x, level.start.y)
  if startCell then
    carveCell(level, level.start.x, level.start.y, "atrium", 0.82, "flagstone", "atrium")
  end

  sealUnreachableCells(level)
  return level
end

function Level.generate(width, height)
  local last

  for _ = 1, 8 do
    local level = generateMegastructure(width or Level.width, height or Level.height)
    last = level
    if validateLevel(level) then
      return level
    end
  end

  validateLevel(last)
  return last
end

return Level
