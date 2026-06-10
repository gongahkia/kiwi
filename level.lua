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
}

local zoneStyles = {
  ["atrium"] = { terrain = "flagstone", light = 0.78, ceiling = 4.2 },
  ["upper nave"] = { terrain = "flagstone", light = 0.68, ceiling = 3.6 },
  ["lower foundry"] = { terrain = "grate", light = 0.66, ceiling = 3.1 },
  ["archive"] = { terrain = "dust", light = 0.54, ceiling = 3.0 },
  ["observatory"] = { terrain = "glass", light = 0.72, ceiling = 3.8 },
  ["cistern"] = { terrain = "water", light = 0.5, ceiling = 3.1 },
  ["overgrown court"] = { terrain = "moss", light = 0.7, ceiling = 3.4 },
  ["quarry"] = { terrain = "rubble", light = 0.58, ceiling = 3.6 },
  ["machine shaft"] = { terrain = "grate", light = 0.62, ceiling = 3.4 },
  ["bridgeworks"] = { terrain = "catwalk", light = 0.64, ceiling = 3.2 },
  ["annex"] = { terrain = "stone", light = 0.58, ceiling = 3.0 },
  ["chamber"] = { terrain = "stone", light = 0.56, ceiling = 2.8 },
  ["hall"] = { terrain = "stone", light = 0.5, ceiling = 2.55 },
  ["stairs"] = { terrain = "steps", light = 0.62, ceiling = 2.55 },
  ["ladder"] = { terrain = "ladder", light = 0.68, ceiling = 3.0 },
}

Level.terrainSpeed = {
  flagstone = 1,
  stone = 1,
  steps = 0.92,
  dust = 0.95,
  grate = 0.9,
  catwalk = 0.88,
  glass = 0.94,
  moss = 0.84,
  rubble = 0.74,
  water = 0.66,
  slag = 0.7,
  ladder = 0.48,
}

Level.terrainLabels = {
  flagstone = "FLAGSTONE",
  stone = "STONE",
  steps = "STAIRS",
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

local extraRoomKinds = {
  "cistern",
  "overgrown court",
  "quarry",
  "machine shaft",
  "bridgeworks",
  "archive",
}

local objectiveLabels = {
  "NORTH RELAY",
  "WEST RELAY",
  "SOUTH RELAY",
  "EAST RELAY",
  "DEEP RELAY",
}

local function zoneStyle(kind)
  return zoneStyles[kind] or zoneStyles.chamber
end

local function makeWallCell()
  return {
    solid = true,
    floor = 0,
    ceiling = 2.8,
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

local function carveCell(level, x, y, floorZ, kind, light, ceilingExtra, terrain, zone)
  if x <= 1 or y <= 1 or x >= level.width or y >= level.height then
    return
  end

  local style = zoneStyle(kind or zone or "hall")
  local cell = level.grid[y][x]
  cell.solid = false
  cell.floor = floorZ
  cell.ceiling = floorZ + (ceilingExtra or style.ceiling or 2.55)
  cell.kind = kind or "hall"
  cell.light = light or style.light or 0.55
  cell.stair = kind == "stairs"
  cell.ladder = kind == "ladder"
  cell.terrain = terrain or style.terrain or "stone"
  cell.zone = zone or kind or "hall"
end

local function carveBrush(level, centerX, centerY, radius, floorZ, kind, light, ceilingExtra, terrain, zone)
  for y = centerY - radius, centerY + radius do
    for x = centerX - radius, centerX + radius do
      if abs(x - centerX) + abs(y - centerY) <= radius + 1 then
        carveCell(level, x, y, floorZ, kind, light, ceilingExtra, terrain, zone)
      end
    end
  end
end

local function carveRect(level, x, y, width, height, floorZ, kind, light, ceilingExtra, terrain, zone)
  for yy = y, y + height - 1 do
    for xx = x, x + width - 1 do
      carveCell(level, xx, yy, floorZ, kind, light, ceilingExtra, terrain, zone)
    end
  end
end

local function addRoom(level, centerX, centerY, width, height, floorZ, kind, route)
  local x = U.clamp(floor(centerX - width / 2), 2, level.width - width)
  local y = U.clamp(floor(centerY - height / 2), 2, level.height - height)
  local style = zoneStyle(kind)
  local light = style.light or (0.48 + love.math.random() * 0.24)
  local ceilingExtra = style.ceiling or love.math.random(24, 36) / 10

  carveRect(level, x, y, width, height, floorZ, kind, light, ceilingExtra, style.terrain, kind)

  local room = {
    x = x,
    y = y,
    width = width,
    height = height,
    cx = x + floor(width / 2),
    cy = y + floor(height / 2),
    floor = floorZ,
    kind = kind,
    terrain = style.terrain,
    light = light,
    ceiling = ceilingExtra,
    route = route or false,
  }

  level.rooms[#level.rooms + 1] = room
  if route then
    level.routeRooms[#level.routeRooms + 1] = room
  end
  return room
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

local function connectRooms(level, a, b, width)
  local points = {}
  local bendX
  local bendY

  if love.math.random() < 0.5 then
    bendX = b.cx
    bendY = a.cy
  else
    bendX = a.cx
    bendY = b.cy
  end

  appendLine(points, a.cx, a.cy, bendX, bendY)
  appendLine(points, bendX, bendY, b.cx, b.cy)

  local stairs = abs(a.floor - b.floor) > 0.16

  for i, point in ipairs(points) do
    local t = #points <= 1 and 0 or (i - 1) / (#points - 1)
    local floorZ = U.mix(a.floor, b.floor, t)
    local kind = stairs and "stairs" or "hall"
    local light = stairs and 0.62 or 0.5
    local terrain = stairs and "steps" or "stone"

    carveBrush(level, point[1], point[2], width, floorZ, kind, light, 2.55, terrain, "passage")
  end

  return points
end

local function setTerrain(level, x, y, terrain, floorOffset, light, kind)
  local cell = Level.cellAtCell(level, x, y)

  if not cell or cell.solid then
    return
  end

  local offset = floorOffset or 0
  cell.floor = cell.floor + offset
  cell.ceiling = cell.ceiling + offset
  cell.terrain = terrain or cell.terrain
  cell.light = light or cell.light

  if kind then
    cell.kind = kind
  end
end

local function setSolidFeature(level, x, y, floorZ, kind, light)
  if x <= 1 or y <= 1 or x >= level.width or y >= level.height then
    return
  end

  local cell = level.grid[y][x]
  cell.solid = true
  cell.floor = floorZ or cell.floor
  cell.ceiling = cell.floor + 2.7
  cell.kind = kind or "feature"
  cell.light = light or 0.38
  cell.stair = false
  cell.ladder = false
  cell.terrain = "stone"
end

local function preserveRoomSpine(room, x, y)
  return abs(x - room.cx) <= 1 or abs(y - room.cy) <= 1
end

local function scatterTerrain(level, room, terrain, chance, floorOffsetMin, floorOffsetMax, light)
  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      if not preserveRoomSpine(room, x, y) and love.math.random() < chance then
        local offset = love.math.random(floorOffsetMin, floorOffsetMax) / 100
        setTerrain(level, x, y, terrain, offset, light)
      end
    end
  end
end

local function addFoundryFeatures(level, room)
  for y = room.y + 2, room.y + room.height - 3 do
    for x = room.x + 2, room.x + room.width - 3 do
      if x % 4 == 0 then
        setTerrain(level, x, y, "catwalk", 0.18, 0.7, "catwalk")
      elseif y % 5 == 0 and love.math.random() < 0.45 then
        setTerrain(level, x, y, "slag", -0.18, 0.82, "slag")
      end
    end
  end
end

local function addArchiveFeatures(level, room)
  for x = room.x + 3, room.x + room.width - 3, 4 do
    for y = room.y + 2, room.y + room.height - 3 do
      if abs(y - room.cy) > 1 and love.math.random() < 0.74 then
        setSolidFeature(level, x, y, room.floor, "stacks", 0.35)
      end
    end
  end

  scatterTerrain(level, room, "dust", 0.35, -5, 2, 0.5)
end

local function addCisternFeatures(level, room)
  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      if abs(x - room.cx) > 1 and abs(y - room.cy) > 1 then
        setTerrain(level, x, y, "water", -0.32, 0.48, "cistern")
      elseif x == room.cx or y == room.cy then
        setTerrain(level, x, y, "catwalk", 0.16, 0.62, "catwalk")
      end
    end
  end
end

local function addOvergrowthFeatures(level, room)
  scatterTerrain(level, room, "moss", 0.58, -3, 8, 0.68)

  for _ = 1, 8 do
    local x = love.math.random(room.x + 2, room.x + room.width - 3)
    local y = love.math.random(room.y + 2, room.y + room.height - 3)

    if not preserveRoomSpine(room, x, y) then
      setSolidFeature(level, x, y, room.floor, "root mass", 0.46)
    end
  end
end

local function addQuarryFeatures(level, room)
  scatterTerrain(level, room, "rubble", 0.5, -18, 24, 0.55)

  for y = room.y + 2, room.y + room.height - 3, 3 do
    for x = room.x + 2, room.x + room.width - 3 do
      if abs(x - room.cx) > 1 then
        setTerrain(level, x, y, "rubble", 0.22, 0.58, "ledge")
      end
    end
  end
end

local function addObservatoryFeatures(level, room)
  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      local distance = sqrt((x - room.cx) ^ 2 + (y - room.cy) ^ 2)

      if distance < min(room.width, room.height) * 0.22 then
        setTerrain(level, x, y, "glass", 0.35, 0.76, "dais")
      elseif distance > min(room.width, room.height) * 0.39 and love.math.random() < 0.35 then
        setTerrain(level, x, y, "rubble", -0.12, 0.6, "broken rim")
      end
    end
  end
end

local function addMachineFeatures(level, room)
  for y = room.y + 2, room.y + room.height - 3 do
    for x = room.x + 2, room.x + room.width - 3 do
      if y % 4 == 0 then
        setTerrain(level, x, y, "grate", 0.1, 0.68, "service deck")
      elseif x % 5 == 0 and not preserveRoomSpine(room, x, y) then
        setSolidFeature(level, x, y, room.floor, "machinery", 0.4)
      end
    end
  end
end

local function addBridgeFeatures(level, room)
  for y = room.y + 1, room.y + room.height - 2 do
    for x = room.x + 1, room.x + room.width - 2 do
      if abs(y - room.cy) <= 1 or abs(x - room.cx) <= 1 then
        setTerrain(level, x, y, "catwalk", 0.22, 0.66, "bridge")
      elseif love.math.random() < 0.58 then
        setTerrain(level, x, y, "rubble", -0.26, 0.43, "drop floor")
      end
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
    scatterTerrain(level, room, "rubble", 0.18, -10, 14, 0.54)
  end

  local startCell = Level.cellAtCell(level, room.cx, room.cy)
  if startCell then
    startCell.solid = false
    startCell.floor = room.floor
    startCell.ceiling = room.floor + room.ceiling
    startCell.terrain = room.terrain or startCell.terrain
    startCell.light = max(startCell.light or 0.5, room.light or 0.5)
  end
end

local function addLadderLink(level, a, b)
  if abs(a.floor - b.floor) < 0.72 then
    return false
  end

  local horizontal = abs(b.cx - a.cx) > abs(b.cy - a.cy)
  local lx = U.clamp(floor((a.cx + b.cx) / 2) + love.math.random(-3, 3), 4, level.width - 4)
  local ly = U.clamp(floor((a.cy + b.cy) / 2) + love.math.random(-3, 3), 4, level.height - 4)
  local ax, ay = lx, ly
  local bx = lx + (horizontal and U.sign(b.cx - a.cx) or 0)
  local by = ly + (horizontal and 0 or U.sign(b.cy - a.cy))

  if bx == ax and by == ay then
    bx = ax + 1
  end

  bx = U.clamp(bx, 3, level.width - 2)
  by = U.clamp(by, 3, level.height - 2)

  local low = { cx = ax, cy = ay, floor = a.floor }
  local high = { cx = bx, cy = by, floor = b.floor }

  connectRooms(level, a, low, 1)
  connectRooms(level, high, b, 1)

  carveCell(level, ax, ay, a.floor, "ladder", 0.72, 3.15, "ladder", "shaft")
  carveCell(level, bx, by, b.floor, "ladder", 0.72, 3.15, "ladder", "shaft")

  return true
end

local function addColumns(level)
  for _, room in ipairs(level.rooms) do
    if room.width >= 10 and room.height >= 9 then
      for y = room.y + 3, room.y + room.height - 4, 4 do
        for x = room.x + 3, room.x + room.width - 4, 5 do
          local centerDistance = sqrt((x - room.cx) ^ 2 + (y - room.cy) ^ 2)

          if centerDistance > 3.2 and love.math.random() < 0.38 then
            local cell = level.grid[y][x]
            cell.solid = true
            cell.floor = room.floor
            cell.ceiling = room.floor + 3.1
            cell.kind = "column"
            cell.light = 0.42
            cell.stair = false
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

  for y = 1, level.height do
    for x = 1, level.width do
      local cell = level.grid[y][x]
      if not cell.solid then
        terrainCounts[cell.terrain] = (terrainCounts[cell.terrain] or 0) + 1
        zoneCounts[cell.zone] = (zoneCounts[cell.zone] or 0) + 1

        if cell.stair then
          stairCount = stairCount + 1
        end

        if cell.ladder then
          ladderCount = ladderCount + 1
        end
      end
    end
  end

  level.stairCount = stairCount
  level.ladderCount = ladderCount
  level.terrainCounts = terrainCounts
  level.zoneCounts = zoneCounts
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

  local heightDelta = abs(b.floor - a.floor)
  return heightDelta <= Level.maxStepHeight or a.stair or b.stair or (a.ladder and b.ladder)
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
          local fromCell = Level.cellAtCell(level, current.x, current.y)
          local toCell = Level.cellAtCell(level, nx, ny)
          local terrainCost = 1 / max(0.35, Level.terrainSpeed[toCell.terrain] or 1)
          local ladderCost = toCell.ladder and 1.6 or 0
          local stepCost = terrainCost + abs(toCell.floor - fromCell.floor) * 0.35 + ladderCost
          local tentativeG = current.g + stepCost

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
  local x = U.clamp(room.cx + love.math.random(-2, 2), room.x + 1, room.x + room.width - 2)
  local y = U.clamp(room.cy + love.math.random(-2, 2), room.y + 1, room.y + room.height - 2)
  local cell = Level.cellAtCell(level, x, y)

  if not cell or cell.solid or cell.objective then
    return
  end

  cell.refill = true
  cell.refillUsed = false
  cell.kind = "oil cache"
  cell.light = max(cell.light or 0.5, 0.76)
  level.refills[#level.refills + 1] = { x = x, y = y, cell = cell }
end

local function markShortcutGate(level, points, required)
  if #points < 5 then
    return
  end

  local point = points[floor(#points / 2)]
  local cell = Level.cellAtCell(level, point[1], point[2])
  if not cell or cell.solid or cell.objective then
    return
  end

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

local function placeObjectivesAndGates(level)
  for i = 2, min(#level.routeRooms, 5) do
    markObjective(level, level.routeRooms[i], i - 1)
  end

  local refillBudget = 7
  for i = #level.rooms, 1, -1 do
    local room = level.rooms[i]
    if not room.route and refillBudget > 0 and love.math.random() < 0.72 then
      markRefill(level, room)
      refillBudget = refillBudget - 1
    end
  end

  if #level.routeRooms >= 5 then
    markShortcutGate(level, connectRooms(level, level.routeRooms[2], level.routeRooms[4], 1), 2)
    markShortcutGate(level, connectRooms(level, level.routeRooms[3], level.routeRooms[5], 1), 3)
  end
end

local function ensureVerticalLinks(level)
  local lowest = level.rooms[1]
  local highest = level.rooms[1]

  for _, room in ipairs(level.rooms) do
    if room.floor < lowest.floor then
      lowest = room
    end
    if room.floor > highest.floor then
      highest = room
    end
  end

  addLadderLink(level, lowest, highest)
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
  requireValid(#level.objectives >= 3, "objectives")
  requireValid(objectiveReachable == #level.objectives, "objective-reachability")
  requireValid(atriumEscapeReachable == #level.objectives, "atrium-escape")
  requireValid(#level.gates >= 2, "gates")
  requireValid(gateReachable == #level.gates, "gate-reachability")
  requireValid(gateUsable == #level.gates, "gate-usability")
  requireValid(level.stairCount > 0, "stairs")
  requireValid(level.ladderCount >= 2, "ladders")
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
    gates = #level.gates,
    stairs = level.stairCount,
    ladders = level.ladderCount,
  }

  return level.validation
end

local function validateLevel(level)
  return Level.validate(level).valid
end

local function generateMegastructure(width, height)
  local level = makeLevel(width, height)
  local cx = floor(width / 2)
  local cy = floor(height / 2)
  local center = addRoom(level, cx, cy, love.math.random(13, 17), love.math.random(11, 15), 0, "atrium", true)

  level.start = { x = center.cx, y = center.cy }

  local routeSpecs = {
    { 0, -1, 1.15, "upper nave" },
    { -1, 0, 1.75, "observatory" },
    { 0, 1, 0.75, "archive" },
    { 1, 0, -1.0, "lower foundry" },
  }

  local previous = center

  for _, spec in ipairs(routeSpecs) do
    local dx, dy, floorZ, kind = spec[1], spec[2], spec[3], spec[4]
    local distance = love.math.random(15, 19)
    local room = addRoom(
      level,
      cx + dx * distance + love.math.random(-3, 3),
      cy + dy * distance + love.math.random(-3, 3),
      love.math.random(10, 15),
      love.math.random(9, 13),
      floorZ,
      kind,
      true
    )

    connectRooms(level, previous, room, 1)
    previous = room
  end

  for _, anchor in ipairs(level.routeRooms) do
    if anchor ~= center and love.math.random() < 0.9 then
      local vx = anchor.cx - center.cx
      local vy = anchor.cy - center.cy
      local length = max(1, sqrt(vx * vx + vy * vy))
      local floorOffset = ({ -0.7, 0.0, 0.65, 1.05 })[love.math.random(4)]
      local kind = extraRoomKinds[love.math.random(#extraRoomKinds)]
      local room = addRoom(
        level,
        anchor.cx + floor(vx / length * love.math.random(9, 13)) + love.math.random(-2, 2),
        anchor.cy + floor(vy / length * love.math.random(9, 13)) + love.math.random(-2, 2),
        love.math.random(8, 13),
        love.math.random(7, 11),
        anchor.floor + floorOffset,
        kind,
        false
      )

      connectRooms(level, anchor, room, 1)
    end
  end

  for _ = 1, 8 do
    local anchor = level.rooms[love.math.random(#level.rooms)]
    local direction = U.neighbors[love.math.random(#U.neighbors)]
    local floorZ = anchor.floor + love.math.random(-3, 3) * 0.25
    local kind = love.math.random() < 0.55 and extraRoomKinds[love.math.random(#extraRoomKinds)] or "chamber"
    local room = addRoom(
      level,
      anchor.cx + direction[1] * love.math.random(9, 15) + love.math.random(-3, 3),
      anchor.cy + direction[2] * love.math.random(9, 15) + love.math.random(-3, 3),
      love.math.random(5, 9),
      love.math.random(5, 9),
      floorZ,
      kind,
      false
    )

    connectRooms(level, anchor, room, love.math.random() < 0.35 and 2 or 1)
  end

  for _, room in ipairs(level.rooms) do
    decorateRoom(level, room)
  end

  for _ = 1, 8 do
    local a = level.rooms[love.math.random(#level.rooms)]
    local b = level.rooms[love.math.random(#level.rooms)]

    if a ~= b then
      addLadderLink(level, a, b)
    end
  end

  ensureVerticalLinks(level)
  addColumns(level)
  placeObjectivesAndGates(level)

  local startCell = Level.cellAtCell(level, level.start.x, level.start.y)
  if startCell then
    startCell.solid = false
    startCell.kind = "atrium"
    startCell.floor = 0
    startCell.ceiling = 4.2
    startCell.light = 0.78
    startCell.stair = false
    startCell.ladder = false
    startCell.terrain = "flagstone"
    startCell.zone = "atrium"
  end

  sealUnreachableCells(level)
  countFeatures(level)
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
