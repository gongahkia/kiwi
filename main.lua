local floor = math.floor
local ceil = math.ceil
local abs = math.abs
local min = math.min
local max = math.max
local sqrt = math.sqrt
local cos = math.cos
local sin = math.sin
local tan = math.tan

local function clamp(value, low, high)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

local function mix(a, b, t)
  return a + (b - a) * t
end

local function keyOf(x, y)
  return x .. ":" .. y
end

local game = {
  level = nil,
  player = nil,
  enemy = nil,
  showMap = false,
  state = "playing",
  survivalTime = 0,
  bestTime = 0,
  seed = 0,
  fonts = {},
}

local levelWidth = 57
local levelHeight = 57
local rayStep = 2
local wallRenderDistance = 32
local maxStepHeight = 0.58
local eyeHeight = 0.72
local playerHeight = 1.55

local neighbors = {
  { 1, 0 },
  { -1, 0 },
  { 0, 1 },
  { 0, -1 },
}

local function makeWallCell()
  return {
    solid = true,
    floor = 0,
    ceiling = 2.8,
    kind = "wall",
    light = 0.3,
    stair = false,
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
    start = { x = floor(width / 2), y = floor(height / 2) },
    stairCount = 0,
  }
end

local function cellAtCell(level, x, y)
  if not level or x < 1 or y < 1 or x > level.width or y > level.height then
    return nil
  end

  return level.grid[y][x]
end

local function cellAtWorld(level, worldX, worldY)
  return cellAtCell(level, floor(worldX), floor(worldY))
end

local function carveCell(level, x, y, floorZ, kind, light, ceilingExtra)
  if x <= 1 or y <= 1 or x >= level.width or y >= level.height then
    return
  end

  local cell = level.grid[y][x]
  cell.solid = false
  cell.floor = floorZ
  cell.ceiling = floorZ + (ceilingExtra or 2.55)
  cell.kind = kind or "hall"
  cell.light = light or 0.55
  cell.stair = kind == "stairs"
end

local function carveBrush(level, centerX, centerY, radius, floorZ, kind, light, ceilingExtra)
  for y = centerY - radius, centerY + radius do
    for x = centerX - radius, centerX + radius do
      if abs(x - centerX) + abs(y - centerY) <= radius + 1 then
        carveCell(level, x, y, floorZ, kind, light, ceilingExtra)
      end
    end
  end
end

local function carveRect(level, x, y, width, height, floorZ, kind, light, ceilingExtra)
  for yy = y, y + height - 1 do
    for xx = x, x + width - 1 do
      carveCell(level, xx, yy, floorZ, kind, light, ceilingExtra)
    end
  end
end

local function addRoom(level, centerX, centerY, width, height, floorZ, kind)
  local x = clamp(floor(centerX - width / 2), 2, level.width - width)
  local y = clamp(floor(centerY - height / 2), 2, level.height - height)
  local light = kind == "atrium" and 0.78 or 0.48 + love.math.random() * 0.24
  local ceilingExtra = kind == "atrium" and 4.2 or love.math.random(24, 36) / 10

  carveRect(level, x, y, width, height, floorZ, kind, light, ceilingExtra)

  local room = {
    x = x,
    y = y,
    width = width,
    height = height,
    cx = x + floor(width / 2),
    cy = y + floor(height / 2),
    floor = floorZ,
    kind = kind,
  }

  level.rooms[#level.rooms + 1] = room
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
    local floorZ = mix(a.floor, b.floor, t)
    local kind = stairs and "stairs" or "hall"
    local light = stairs and 0.62 or 0.5

    carveBrush(level, point[1], point[2], width, floorZ, kind, light, 2.55)
  end
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

local function countStairs(level)
  local count = 0

  for y = 1, level.height do
    for x = 1, level.width do
      local cell = level.grid[y][x]
      if not cell.solid and cell.stair then
        count = count + 1
      end
    end
  end

  level.stairCount = count
end

local function generateMegastructure(width, height)
  local level = makeLevel(width, height)
  local cx = floor(width / 2)
  local cy = floor(height / 2)
  local center = addRoom(level, cx, cy, love.math.random(13, 17), love.math.random(11, 15), 0, "atrium")

  level.start = { x = center.cx, y = center.cy }

  local wingSpecs = {
    { 0, -1, 1.15, "upper nave" },
    { 1, 0, -1.0, "lower foundry" },
    { 0, 1, 0.75, "archive" },
    { -1, 0, 1.75, "observatory" },
  }

  local wings = {}

  for _, spec in ipairs(wingSpecs) do
    local dx, dy, floorZ, kind = spec[1], spec[2], spec[3], spec[4]
    local distance = love.math.random(15, 19)
    local room = addRoom(
      level,
      cx + dx * distance + love.math.random(-3, 3),
      cy + dy * distance + love.math.random(-3, 3),
      love.math.random(10, 15),
      love.math.random(9, 13),
      floorZ,
      kind
    )

    connectRooms(level, center, room, 1)
    wings[#wings + 1] = room
  end

  for i, wing in ipairs(wings) do
    local nextWing = wings[(i % #wings) + 1]
    if love.math.random() < 0.75 then
      connectRooms(level, wing, nextWing, 1)
    end
  end

  for _, wing in ipairs(wings) do
    if love.math.random() < 0.85 then
      local vx = wing.cx - center.cx
      local vy = wing.cy - center.cy
      local length = max(1, sqrt(vx * vx + vy * vy))
      local floorOffset = ({ -0.7, 0.0, 0.65, 1.05 })[love.math.random(4)]
      local room = addRoom(
        level,
        wing.cx + floor(vx / length * love.math.random(10, 14)) + love.math.random(-2, 2),
        wing.cy + floor(vy / length * love.math.random(10, 14)) + love.math.random(-2, 2),
        love.math.random(8, 13),
        love.math.random(7, 11),
        wing.floor + floorOffset,
        "annex"
      )

      connectRooms(level, wing, room, 1)
    end
  end

  for _ = 1, 7 do
    local anchor = level.rooms[love.math.random(#level.rooms)]
    local direction = neighbors[love.math.random(#neighbors)]
    local floorZ = anchor.floor + love.math.random(-3, 3) * 0.25
    local room = addRoom(
      level,
      anchor.cx + direction[1] * love.math.random(9, 15) + love.math.random(-3, 3),
      anchor.cy + direction[2] * love.math.random(9, 15) + love.math.random(-3, 3),
      love.math.random(5, 9),
      love.math.random(5, 9),
      floorZ,
      "chamber"
    )

    connectRooms(level, anchor, room, love.math.random() < 0.35 and 2 or 1)
  end

  addColumns(level)
  countStairs(level)

  local startCell = cellAtCell(level, level.start.x, level.start.y)
  if startCell then
    startCell.solid = false
    startCell.kind = "atrium"
    startCell.floor = 0
    startCell.ceiling = 4.2
    startCell.light = 0.78
    startCell.stair = false
  end

  return level
end

local function isWalkableCell(x, y)
  local cell = cellAtCell(game.level, x, y)
  return cell ~= nil and not cell.solid
end

local function canTraverseCells(ax, ay, bx, by)
  local a = cellAtCell(game.level, ax, ay)
  local b = cellAtCell(game.level, bx, by)

  if not a or not b or a.solid or b.solid then
    return false
  end

  if ax == bx and ay == by then
    return true
  end

  local heightDelta = abs(b.floor - a.floor)
  return heightDelta <= maxStepHeight or a.stair or b.stair
end

local function wallAt(worldX, worldY)
  local cell = cellAtWorld(game.level, worldX, worldY)
  return cell == nil or cell.solid
end

local function canOccupyFrom(entity, x, y, radius)
  local fromX = floor(entity.x)
  local fromY = floor(entity.y)
  local samples = {
    { x, y },
    { x - radius, y - radius },
    { x + radius, y - radius },
    { x - radius, y + radius },
    { x + radius, y + radius },
  }

  for _, sample in ipairs(samples) do
    local targetX = floor(sample[1])
    local targetY = floor(sample[2])

    if wallAt(sample[1], sample[2]) or not canTraverseCells(fromX, fromY, targetX, targetY) then
      return false
    end
  end

  return true
end

local function moveWithCollision(entity, dx, dy)
  if canOccupyFrom(entity, entity.x + dx, entity.y, entity.radius) then
    entity.x = entity.x + dx
  end

  if canOccupyFrom(entity, entity.x, entity.y + dy, entity.radius) then
    entity.y = entity.y + dy
  end
end

local function floorAt(worldX, worldY)
  local cell = cellAtWorld(game.level, worldX, worldY)
  if cell and not cell.solid then
    return cell.floor
  end

  return 0
end

local function updateActorHeight(actor, dt)
  local targetFloor = floorAt(actor.x, actor.y)
  actor.floorZ = actor.floorZ or targetFloor
  actor.floorZ = mix(actor.floorZ, targetFloor, clamp(dt * 12, 0, 1))
  actor.eyeZ = actor.floorZ + (actor.eyeHeight or eyeHeight)
end

local function farthestCellFrom(startX, startY)
  local queue = { { startX, startY } }
  local head = 1
  local visited = { [keyOf(startX, startY)] = true }
  local farthest = { x = startX, y = startY, distance = 0 }
  local distances = { [keyOf(startX, startY)] = 0 }

  while head <= #queue do
    local current = queue[head]
    head = head + 1
    local x, y = current[1], current[2]
    local distance = distances[keyOf(x, y)] or 0

    if distance > farthest.distance then
      farthest = { x = x, y = y, distance = distance }
    end

    for _, neighbor in ipairs(neighbors) do
      local nx, ny = x + neighbor[1], y + neighbor[2]
      local neighborKey = keyOf(nx, ny)

      if not visited[neighborKey] and canTraverseCells(x, y, nx, ny) then
        visited[neighborKey] = true
        distances[neighborKey] = distance + 1
        queue[#queue + 1] = { nx, ny }
      end
    end
  end

  return farthest
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
    current = cameFrom[keyOf(current.x, current.y)]
  end

  return path
end

local function findPath(startX, startY, goalX, goalY)
  if not isWalkableCell(startX, startY) or not isWalkableCell(goalX, goalY) then
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
  local gScore = { [keyOf(startX, startY)] = 0 }
  local closed = {}

  while #open > 0 do
    local bestIndex = 1

    for i = 2, #open do
      if open[i].f < open[bestIndex].f then
        bestIndex = i
      end
    end

    local current = table.remove(open, bestIndex)
    local currentKey = keyOf(current.x, current.y)

    if not closed[currentKey] then
      if current.x == goalX and current.y == goalY then
        return reconstructPath(cameFrom, startX, startY, goalX, goalY)
      end

      closed[currentKey] = true

      for _, neighbor in ipairs(neighbors) do
        local nx, ny = current.x + neighbor[1], current.y + neighbor[2]
        local neighborKey = keyOf(nx, ny)

        if canTraverseCells(current.x, current.y, nx, ny) and not closed[neighborKey] then
          local fromCell = cellAtCell(game.level, current.x, current.y)
          local toCell = cellAtCell(game.level, nx, ny)
          local stepCost = 1 + abs(toCell.floor - fromCell.floor) * 0.35
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

local function lineOfSight(ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local distance = sqrt(dx * dx + dy * dy)

  if distance <= 0 then
    return true
  end

  local steps = ceil(distance / 0.08)

  for i = 1, steps do
    local t = i / steps
    local x = ax + dx * t
    local y = ay + dy * t

    if wallAt(x, y) then
      return false
    end
  end

  return true
end

local function startGame()
  game.seed = os.time() + floor(love.timer.getTime() * 1000)
  love.math.setRandomSeed(game.seed)

  game.level = generateMegastructure(levelWidth, levelHeight)
  game.player = {
    x = game.level.start.x + 0.5,
    y = game.level.start.y + 0.5,
    angle = 0,
    fov = math.rad(66),
    radius = 0.18,
    speed = 2.62,
    sprintSpeed = 3.75,
    turnSpeed = 2.55,
    bob = 0,
    moving = false,
    eyeHeight = eyeHeight,
    floorZ = 0,
    eyeZ = eyeHeight,
  }

  updateActorHeight(game.player, 1)

  local spawn = farthestCellFrom(game.level.start.x, game.level.start.y)

  game.enemy = {
    x = spawn.x + 0.5,
    y = spawn.y + 0.5,
    radius = 0.2,
    baseSpeed = 1.34,
    sightSpeed = 1.76,
    path = {},
    pathTimer = 0,
    repathDelay = 0.22,
    visible = false,
    growl = 0,
    eyeHeight = 0.82,
    floorZ = floorAt(spawn.x + 0.5, spawn.y + 0.5),
    eyeZ = floorAt(spawn.x + 0.5, spawn.y + 0.5) + 0.82,
  }

  game.state = "playing"
  game.survivalTime = 0
  love.mouse.setRelativeMode(true)
end

local function updatePlayer(dt)
  local player = game.player
  local turn = 0

  if love.keyboard.isDown("left") or love.keyboard.isDown("q") then
    turn = turn - 1
  end

  if love.keyboard.isDown("right") or love.keyboard.isDown("e") then
    turn = turn + 1
  end

  player.angle = player.angle + turn * player.turnSpeed * dt

  local forward = 0
  local strafe = 0

  if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
    forward = forward + 1
  end

  if love.keyboard.isDown("s") or love.keyboard.isDown("down") then
    forward = forward - 1
  end

  if love.keyboard.isDown("a") then
    strafe = strafe - 1
  end

  if love.keyboard.isDown("d") then
    strafe = strafe + 1
  end

  local length = sqrt(forward * forward + strafe * strafe)
  player.moving = length > 0

  if length > 0 then
    forward = forward / length
    strafe = strafe / length
  end

  local sprinting = forward > 0 and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift"))
  local speed = sprinting and player.sprintSpeed or player.speed
  local dirX, dirY = cos(player.angle), sin(player.angle)
  local strafeX, strafeY = -dirY, dirX
  local dx = (dirX * forward + strafeX * strafe) * speed * dt
  local dy = (dirY * forward + strafeY * strafe) * speed * dt

  moveWithCollision(player, dx, dy)
  updateActorHeight(player, dt)

  if player.moving then
    player.bob = player.bob + dt * (sprinting and 12 or 8)
  else
    player.bob = player.bob + dt * 2
  end
end

local function updateEnemy(dt)
  local enemy = game.enemy
  local player = game.player
  local dx, dy = player.x - enemy.x, player.y - enemy.y
  local z = (player.floorZ or 0) - (enemy.floorZ or 0)
  local distance = sqrt(dx * dx + dy * dy + z * z * 0.35)

  enemy.visible = lineOfSight(enemy.x, enemy.y, player.x, player.y)
  enemy.pathTimer = enemy.pathTimer - dt
  enemy.growl = clamp(enemy.growl - dt * 0.75, 0, 1)

  if enemy.visible then
    enemy.growl = 1
  end

  if enemy.pathTimer <= 0 then
    local startX, startY = floor(enemy.x), floor(enemy.y)
    local goalX, goalY = floor(player.x), floor(player.y)
    enemy.path = findPath(startX, startY, goalX, goalY)
    enemy.pathTimer = enemy.repathDelay
  end

  local targetX, targetY

  if enemy.visible or #enemy.path == 0 then
    targetX, targetY = player.x, player.y
  else
    local waypoint = enemy.path[1]
    targetX, targetY = waypoint.x, waypoint.y

    if sqrt((targetX - enemy.x) ^ 2 + (targetY - enemy.y) ^ 2) < 0.12 then
      table.remove(enemy.path, 1)
      waypoint = enemy.path[1]

      if waypoint then
        targetX, targetY = waypoint.x, waypoint.y
      else
        targetX, targetY = player.x, player.y
      end
    end
  end

  local moveX, moveY = targetX - enemy.x, targetY - enemy.y
  local moveLength = sqrt(moveX * moveX + moveY * moveY)

  if moveLength > 0.001 then
    local speed = enemy.visible and enemy.sightSpeed or enemy.baseSpeed
    local pressure = clamp(1 - distance / 18, 0, 0.35)

    moveX = (moveX / moveLength) * (speed + pressure) * dt
    moveY = (moveY / moveLength) * (speed + pressure) * dt
    moveWithCollision(enemy, moveX, moveY)
  end

  updateActorHeight(enemy, dt)

  dx, dy = player.x - enemy.x, player.y - enemy.y
  z = (player.floorZ or 0) - (enemy.floorZ or 0)
  distance = sqrt(dx * dx + dy * dy + z * z * 0.35)
  local caughtDistance = player.radius + enemy.radius + 0.12

  if distance < caughtDistance then
    game.state = "caught"
    game.bestTime = max(game.bestTime, game.survivalTime)
    love.mouse.setRelativeMode(false)
  end
end

local function projectWorldZ(worldZ, distance, height)
  local scale = height * 0.86 / max(distance, 0.035)
  return height * 0.54 - (worldZ - game.player.eyeZ) * scale
end

local function drawBackground(width, height)
  local horizon = height * 0.54

  for y = 0, horizon, 6 do
    local t = y / horizon
    love.graphics.setColor(0.035 + t * 0.035, 0.037 + t * 0.03, 0.047 + t * 0.045)
    love.graphics.rectangle("fill", 0, y, width, 7)
  end

  for y = horizon, height, 6 do
    local t = (y - horizon) / (height - horizon)
    love.graphics.setColor(0.15 - t * 0.055, 0.125 - t * 0.045, 0.09 - t * 0.035)
    love.graphics.rectangle("fill", 0, y, width, 7)
  end

  love.graphics.setColor(0.23, 0.17, 0.11, 0.22)
  love.graphics.rectangle("fill", 0, horizon - 1, width, 2)
end

local function castRay(rayDirX, rayDirY)
  local player = game.player
  local mapX = floor(player.x)
  local mapY = floor(player.y)
  local previousCell = cellAtCell(game.level, mapX, mapY)
  local deltaDistX = rayDirX == 0 and 1e30 or abs(1 / rayDirX)
  local deltaDistY = rayDirY == 0 and 1e30 or abs(1 / rayDirY)
  local stepX, stepY
  local sideDistX, sideDistY
  local side = 0
  local segments = {}

  if rayDirX < 0 then
    stepX = -1
    sideDistX = (player.x - mapX) * deltaDistX
  else
    stepX = 1
    sideDistX = (mapX + 1 - player.x) * deltaDistX
  end

  if rayDirY < 0 then
    stepY = -1
    sideDistY = (player.y - mapY) * deltaDistY
  else
    stepY = 1
    sideDistY = (mapY + 1 - player.y) * deltaDistY
  end

  for _ = 1, 180 do
    local distance

    if sideDistX < sideDistY then
      sideDistX = sideDistX + deltaDistX
      mapX = mapX + stepX
      side = 0
      distance = (mapX - player.x + (1 - stepX) / 2) / rayDirX
    else
      sideDistY = sideDistY + deltaDistY
      mapY = mapY + stepY
      side = 1
      distance = (mapY - player.y + (1 - stepY) / 2) / rayDirY
    end

    distance = max(distance, 0.01)

    local nextCell = cellAtCell(game.level, mapX, mapY)

    if not nextCell or nextCell.solid then
      if previousCell then
        segments[#segments + 1] = {
          distance = distance,
          bottom = previousCell.floor,
          top = previousCell.ceiling,
          side = side,
          cell = previousCell,
          mapX = mapX,
          mapY = mapY,
          kind = nextCell and nextCell.kind or "outer",
          solid = true,
        }
      end

      return segments, distance
    end

    if previousCell then
      if nextCell.floor > previousCell.floor + 0.04 then
        segments[#segments + 1] = {
          distance = distance,
          bottom = previousCell.floor,
          top = nextCell.floor,
          side = side,
          cell = nextCell,
          mapX = mapX,
          mapY = mapY,
          kind = nextCell.stair and "stair" or "riser",
          solid = false,
        }
      elseif nextCell.floor < previousCell.floor - 0.04 then
        segments[#segments + 1] = {
          distance = distance,
          bottom = nextCell.floor,
          top = previousCell.floor,
          side = side,
          cell = previousCell,
          mapX = mapX,
          mapY = mapY,
          kind = nextCell.stair and "stair" or "drop",
          solid = false,
        }
      end

      if nextCell.ceiling < previousCell.ceiling - 0.04 then
        segments[#segments + 1] = {
          distance = distance,
          bottom = nextCell.ceiling,
          top = previousCell.ceiling,
          side = side,
          cell = previousCell,
          mapX = mapX,
          mapY = mapY,
          kind = "lintel",
          solid = false,
        }
      end
    end

    previousCell = nextCell
  end

  return segments, wallRenderDistance
end

local function segmentColor(segment, shade)
  local cell = segment.cell or { floor = 0, light = 0.4 }
  local heightTint = clamp((cell.floor + 1.2) / 4.2, 0, 1)
  local red, green, blue

  if segment.kind == "stair" then
    red, green, blue = 0.62, 0.45, 0.27
  elseif segment.kind == "riser" or segment.kind == "drop" then
    red, green, blue = 0.46, 0.42, 0.34
  elseif segment.kind == "lintel" then
    red, green, blue = 0.28, 0.30, 0.34
  elseif segment.kind == "column" then
    red, green, blue = 0.42, 0.38, 0.31
  else
    red = 0.43 + heightTint * 0.12
    green = 0.39 + heightTint * 0.08
    blue = 0.33 + heightTint * 0.06
  end

  local sideShade = segment.side == 1 and 0.78 or 1
  local light = 0.5 + (cell.light or 0.45) * 0.55

  return red * shade * sideShade * light, green * shade * sideShade * light, blue * shade * sideShade * light
end

local function drawSegment(segment, width, height, screenX)
  local distance = max(segment.distance, 0.01)
  local yTop = projectWorldZ(segment.top, distance, height)
  local yBottom = projectWorldZ(segment.bottom, distance, height)
  local drawStart = max(0, floor(min(yTop, yBottom)))
  local drawEnd = min(height, ceil(max(yTop, yBottom)))

  if drawEnd <= drawStart then
    return
  end

  local torchPulse = 0.98 + sin(game.survivalTime * 11.1) * 0.055 + sin(game.survivalTime * 23.7) * 0.025
  local baseShade = clamp(1 - distance / wallRenderDistance, 0.16, 1)
  local torchShade = clamp(1 - distance / 14, 0, 1) * torchPulse * 0.42
  local shade = clamp(baseShade + torchShade, 0.12, 1.18)
  local red, green, blue = segmentColor(segment, shade)

  love.graphics.setColor(red, green, blue)
  love.graphics.rectangle("fill", screenX, drawStart, rayStep + 1, drawEnd - drawStart)

  if segment.kind == "stair" and distance < 10 then
    love.graphics.setColor(red * 1.22, green * 1.14, blue * 0.92, 0.18)
    love.graphics.rectangle("fill", screenX, drawStart, rayStep + 1, 2)
  end
end

local function drawRaycastWorld(width, height)
  local depthBuffer = {}
  local player = game.player
  local dirX, dirY = cos(player.angle), sin(player.angle)
  local planeScale = tan(player.fov / 2)
  local planeX, planeY = -dirY * planeScale, dirX * planeScale

  drawBackground(width, height)

  for screenX = 0, width - 1, rayStep do
    local cameraX = 2 * (screenX + 0.5) / width - 1
    local rayDirX = dirX + planeX * cameraX
    local rayDirY = dirY + planeY * cameraX
    local segments, solidDistance = castRay(rayDirX, rayDirY)

    for i = #segments, 1, -1 do
      drawSegment(segments[i], width, height, screenX)
    end

    for bufferX = screenX, min(screenX + rayStep, width - 1) do
      depthBuffer[bufferX + 1] = solidDistance or wallRenderDistance
    end
  end

  return depthBuffer
end

local function drawEnemySprite(width, height, depthBuffer)
  local enemy = game.enemy
  local player = game.player
  local dx, dy = enemy.x - player.x, enemy.y - player.y
  local dirX, dirY = cos(player.angle), sin(player.angle)
  local planeScale = tan(player.fov / 2)
  local planeX, planeY = -dirY * planeScale, dirX * planeScale
  local determinant = planeX * dirY - dirX * planeY

  if abs(determinant) < 0.00001 then
    return
  end

  local inverseDet = 1 / determinant
  local transformX = inverseDet * (dirY * dx - dirX * dy)
  local transformY = inverseDet * (-planeY * dx + planeX * dy)

  if transformY <= 0.08 then
    return
  end

  local screenX = floor((width / 2) * (1 + transformX / transformY))
  local baseY = projectWorldZ(enemy.floorZ, transformY, height)
  local topY = projectWorldZ(enemy.floorZ + playerHeight, transformY, height)
  local spriteHeight = abs(floor(baseY - topY))
  local spriteWidth = max(8, floor(spriteHeight * 0.46))
  local drawStartX = screenX - spriteWidth / 2
  local drawEndX = screenX + spriteWidth / 2

  if spriteHeight < 4 or drawEndX < 0 or drawStartX > width then
    return
  end

  local visible = false

  for x = max(0, floor(drawStartX)), min(width - 1, floor(drawEndX)), 4 do
    if transformY < (depthBuffer[x + 1] or math.huge) + 0.05 then
      visible = true
      break
    end
  end

  if not visible then
    return
  end

  local bodyAlpha = clamp(1 - transformY / 28, 0.32, 1)
  local bodyWidth = spriteWidth
  local headY = -spriteHeight * 0.58
  local headRadius = max(3, bodyWidth * 0.21)

  love.graphics.push()
  love.graphics.translate(screenX, baseY)

  love.graphics.setColor(0, 0, 0, 0.35 * bodyAlpha)
  love.graphics.ellipse("fill", 0, spriteHeight * 0.03, bodyWidth * 0.36, max(2, spriteHeight * 0.035))

  love.graphics.setColor(0.18, 0.02, 0.018, bodyAlpha)
  love.graphics.polygon(
    "fill",
    -bodyWidth * 0.34,
    -spriteHeight * 0.04,
    -bodyWidth * 0.23,
    -spriteHeight * 0.5,
    0,
    -spriteHeight * 0.78,
    bodyWidth * 0.23,
    -spriteHeight * 0.5,
    bodyWidth * 0.34,
    -spriteHeight * 0.04
  )

  love.graphics.setColor(0.45, 0.035, 0.03, bodyAlpha)
  love.graphics.polygon(
    "fill",
    -bodyWidth * 0.16,
    -spriteHeight * 0.1,
    -bodyWidth * 0.1,
    -spriteHeight * 0.48,
    0,
    -spriteHeight * 0.63,
    bodyWidth * 0.1,
    -spriteHeight * 0.48,
    bodyWidth * 0.16,
    -spriteHeight * 0.1
  )

  love.graphics.setColor(0.08, 0.008, 0.008, bodyAlpha)
  love.graphics.circle("fill", 0, headY, headRadius)

  local eyeGlow = 0.6 + game.enemy.growl * 0.4
  love.graphics.setColor(1.0, 0.76, 0.22, bodyAlpha * eyeGlow)
  love.graphics.circle("fill", -headRadius * 0.38, headY - headRadius * 0.12, max(1.5, headRadius * 0.16))
  love.graphics.circle("fill", headRadius * 0.38, headY - headRadius * 0.12, max(1.5, headRadius * 0.16))

  love.graphics.setColor(0.02, 0, 0, bodyAlpha)
  love.graphics.setLineWidth(max(1, spriteHeight * 0.012))
  love.graphics.line(-headRadius * 0.55, headY + headRadius * 0.38, headRadius * 0.55, headY + headRadius * 0.38)

  love.graphics.pop()
end

local function drawTorch(width, height)
  local player = game.player
  local bob = sin(player.bob) * (player.moving and 7 or 2)
  local flicker = sin(game.survivalTime * 18.5) * 3 + sin(game.survivalTime * 33.7) * 2
  local handY = height - 54 + bob
  local torchX = width * 0.57 + sin(player.bob * 0.5) * 4
  local torchY = height - 102 + bob

  love.graphics.setColor(0.10, 0.055, 0.035, 0.92)
  love.graphics.polygon("fill", width * 0.33, height, width * 0.4, handY - 18, width * 0.52, handY - 4, width * 0.51, height)

  love.graphics.setColor(0.18, 0.10, 0.065, 0.96)
  love.graphics.polygon("fill", width * 0.5, height, torchX - 30, torchY + 72, torchX + 18, torchY + 72, width * 0.68, height)

  love.graphics.setColor(0.27, 0.18, 0.10, 1)
  love.graphics.rectangle("fill", torchX - 9, torchY, 18, 104, 5, 5)

  love.graphics.setColor(0.09, 0.055, 0.032, 1)
  love.graphics.rectangle("fill", torchX - 11, torchY + 16, 22, 10, 3, 3)
  love.graphics.rectangle("fill", torchX - 11, torchY + 52, 22, 10, 3, 3)

  love.graphics.setColor(0.85, 0.55, 0.24, 1)
  love.graphics.rectangle("fill", torchX - 15, torchY - 8, 30, 18, 4, 4)

  love.graphics.setColor(1, 0.78, 0.28, 0.22)
  love.graphics.circle("fill", torchX, torchY - 35, 80 + flicker)
  love.graphics.setColor(1, 0.48, 0.12, 0.58)
  love.graphics.circle("fill", torchX, torchY - 30, 30 + flicker)
  love.graphics.setColor(1, 0.84, 0.34, 0.9)
  love.graphics.polygon("fill", torchX - 14, torchY - 18, torchX, torchY - 72 - flicker, torchX + 14, torchY - 18, torchX + 5, torchY - 2, torchX - 6, torchY - 2)
  love.graphics.setColor(1, 0.95, 0.66, 0.94)
  love.graphics.polygon("fill", torchX - 6, torchY - 18, torchX + 1, torchY - 50 - flicker * 0.5, torchX + 8, torchY - 18, torchX + 2, torchY - 5)

  love.graphics.setColor(0.95, 0.48, 0.12, 0.08)
  love.graphics.circle("fill", width * 0.5, height * 0.55, max(width, height) * 0.42)
end

local function heightColor(floorZ)
  if floorZ < -0.45 then
    return 0.18, 0.27, 0.33
  elseif floorZ < 0.35 then
    return 0.22, 0.20, 0.16
  elseif floorZ < 1.3 then
    return 0.28, 0.24, 0.18
  end

  return 0.33, 0.30, 0.22
end

local function drawMinimap(width, height)
  if not game.showMap then
    return
  end

  local level = game.level
  local size = min(width * 0.3 / level.width, height * 0.36 / level.height, 7)
  local mapWidth = level.width * size
  local mapHeight = level.height * size
  local originX = width - mapWidth - 18
  local originY = 18

  love.graphics.setColor(0, 0, 0, 0.46)
  love.graphics.rectangle("fill", originX - 7, originY - 7, mapWidth + 14, mapHeight + 14, 4, 4)

  for y = 1, level.height do
    for x = 1, level.width do
      local cell = level.grid[y][x]

      if cell.solid then
        love.graphics.setColor(0.08, 0.075, 0.067, 0.9)
      elseif cell.stair then
        love.graphics.setColor(0.78, 0.48, 0.18, 0.88)
      else
        local red, green, blue = heightColor(cell.floor)
        love.graphics.setColor(red, green, blue, 0.82)
      end

      love.graphics.rectangle("fill", originX + (x - 1) * size, originY + (y - 1) * size, size, size)
    end
  end

  local player = game.player
  local enemy = game.enemy
  local px = originX + player.x * size - size
  local py = originY + player.y * size - size
  local ex = originX + enemy.x * size - size
  local ey = originY + enemy.y * size - size

  love.graphics.setColor(1, 0.78, 0.3, 0.95)
  love.graphics.circle("fill", px, py, max(2.5, size * 0.58))
  love.graphics.line(px, py, px + cos(player.angle) * size * 2.4, py + sin(player.angle) * size * 2.4)

  love.graphics.setColor(0.9, 0.08, 0.05, 0.95)
  love.graphics.circle("fill", ex, ey, max(2.5, size * 0.58))

  love.graphics.setColor(0.9, 0.08, 0.05, 0.22)
  for i = 1, #enemy.path - 1 do
    local a = enemy.path[i]
    local b = enemy.path[i + 1]
    love.graphics.line(originX + a.x * size - size, originY + a.y * size - size, originX + b.x * size - size, originY + b.y * size - size)
  end
end

local function drawHud(width, height)
  local player = game.player
  local enemy = game.enemy
  local dx, dy = enemy.x - player.x, enemy.y - player.y
  local z = (enemy.floorZ or 0) - (player.floorZ or 0)
  local distance = sqrt(dx * dx + dy * dy + z * z * 0.35)
  local danger = clamp(1 - distance / 10, 0, 1)

  love.graphics.setFont(game.fonts.hud)
  love.graphics.setColor(0, 0, 0, 0.42)
  love.graphics.rectangle("fill", 18, 18, 234, 92, 4, 4)

  love.graphics.setColor(0.95, 0.88, 0.68)
  love.graphics.print(string.format("TIME   %05.1f", game.survivalTime), 30, 28)
  love.graphics.setColor(0.86 + danger * 0.14, 0.78 - danger * 0.48, 0.55 - danger * 0.45)
  love.graphics.print(string.format("THREAT %02dM", floor(distance)), 30, 55)
  love.graphics.setColor(0.78, 0.72, 0.6)
  love.graphics.print(string.format("LEVEL  %+0.1f", player.floorZ or 0), 30, 82)

  if danger > 0 then
    love.graphics.setColor(0.65, 0.02, 0.015, danger * 0.16)
    love.graphics.rectangle("fill", 0, 0, width, height)
  end

  if game.state == "caught" then
    love.graphics.setColor(0, 0, 0, 0.66)
    love.graphics.rectangle("fill", 0, 0, width, height)

    love.graphics.setFont(game.fonts.title)
    love.graphics.setColor(0.92, 0.08, 0.045)
    love.graphics.printf("CAUGHT", 0, height * 0.34, width, "center")

    love.graphics.setFont(game.fonts.hud)
    love.graphics.setColor(0.95, 0.86, 0.64)
    love.graphics.printf(string.format("SURVIVED %.1f SECONDS   BEST %.1f", game.survivalTime, game.bestTime), 0, height * 0.49, width, "center")
    love.graphics.setColor(0.82, 0.76, 0.66)
    love.graphics.printf("R TO RUN AGAIN", 0, height * 0.58, width, "center")
  end
end

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  game.fonts.hud = love.graphics.newFont(17)
  game.fonts.title = love.graphics.newFont(58)
  startGame()
end

function love.update(dt)
  dt = min(dt, 1 / 30)

  if game.state == "playing" then
    game.survivalTime = game.survivalTime + dt
    updatePlayer(dt)
    updateEnemy(dt)
  end
end

function love.draw()
  local width, height = love.graphics.getDimensions()
  local depthBuffer = drawRaycastWorld(width, height)

  drawEnemySprite(width, height, depthBuffer)
  drawTorch(width, height)
  drawMinimap(width, height)
  drawHud(width, height)
end

function love.keypressed(key)
  if key == "escape" then
    love.mouse.setRelativeMode(not love.mouse.getRelativeMode())
  elseif key == "m" then
    game.showMap = not game.showMap
  elseif key == "r" or (key == "space" and game.state == "caught") then
    startGame()
  elseif key == "n" then
    startGame()
  end
end

function love.mousepressed()
  if game.state == "playing" then
    love.mouse.setRelativeMode(true)
  end
end

function love.mousemoved(_, _, dx)
  if love.mouse.getRelativeMode() and game.state == "playing" then
    game.player.angle = game.player.angle + dx * 0.0024
  end
end
