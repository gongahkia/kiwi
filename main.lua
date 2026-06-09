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

local function keyOf(x, y)
  return x .. ":" .. y
end

local game = {
  maze = nil,
  player = nil,
  enemy = nil,
  showMap = false,
  state = "playing",
  survivalTime = 0,
  bestTime = 0,
  seed = 0,
  fonts = {},
}

local mazeWidth = 33
local mazeHeight = 33
local rayStep = 2
local wallRenderDistance = 24

local function shuffledDirections()
  local directions = {
    { 2, 0 },
    { -2, 0 },
    { 0, 2 },
    { 0, -2 },
  }

  for i = #directions, 2, -1 do
    local j = love.math.random(i)
    directions[i], directions[j] = directions[j], directions[i]
  end

  return directions
end

local function generateMaze(width, height)
  local grid = {}

  for y = 1, height do
    grid[y] = {}
    for x = 1, width do
      grid[y][x] = 1
    end
  end

  local function carve(x, y)
    grid[y][x] = 0

    for _, direction in ipairs(shuffledDirections()) do
      local dx, dy = direction[1], direction[2]
      local nx, ny = x + dx, y + dy

      if nx > 1 and nx < width and ny > 1 and ny < height and grid[ny][nx] == 1 then
        grid[y + dy / 2][x + dx / 2] = 0
        carve(nx, ny)
      end
    end
  end

  carve(2, 2)

  -- Add a few loops so the chase has decisions instead of only dead ends.
  for y = 2, height - 1 do
    for x = 2, width - 1 do
      if grid[y][x] == 1 and love.math.random() < 0.055 then
        local horizontalPassage = grid[y][x - 1] == 0 and grid[y][x + 1] == 0
        local verticalPassage = grid[y - 1][x] == 0 and grid[y + 1][x] == 0

        if horizontalPassage or verticalPassage then
          grid[y][x] = 0
        end
      end
    end
  end

  grid[2][2] = 0

  return {
    width = width,
    height = height,
    grid = grid,
  }
end

local function isWalkableCell(x, y)
  local maze = game.maze
  return maze
    and x >= 1
    and y >= 1
    and x <= maze.width
    and y <= maze.height
    and maze.grid[y][x] == 0
end

local function wallAt(worldX, worldY)
  local maze = game.maze
  local cellX = floor(worldX)
  local cellY = floor(worldY)

  if not maze or cellX < 1 or cellY < 1 or cellX > maze.width or cellY > maze.height then
    return true
  end

  return maze.grid[cellY][cellX] == 1
end

local function canOccupy(x, y, radius)
  return not wallAt(x - radius, y - radius)
    and not wallAt(x + radius, y - radius)
    and not wallAt(x - radius, y + radius)
    and not wallAt(x + radius, y + radius)
    and not wallAt(x, y)
end

local function moveWithCollision(entity, dx, dy)
  if canOccupy(entity.x + dx, entity.y, entity.radius) then
    entity.x = entity.x + dx
  end

  if canOccupy(entity.x, entity.y + dy, entity.radius) then
    entity.y = entity.y + dy
  end
end

local function farthestCellFrom(startX, startY)
  local queue = { { startX, startY } }
  local head = 1
  local visited = { [keyOf(startX, startY)] = true }
  local farthest = { x = startX, y = startY, distance = 0 }
  local distances = { [keyOf(startX, startY)] = 0 }
  local neighbors = {
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
  }

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

      if not visited[neighborKey] and isWalkableCell(nx, ny) then
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
  local neighbors = {
    { 1, 0 },
    { -1, 0 },
    { 0, 1 },
    { 0, -1 },
  }

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

        if isWalkableCell(nx, ny) and not closed[neighborKey] then
          local tentativeG = current.g + 1

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

  game.maze = generateMaze(mazeWidth, mazeHeight)
  game.player = {
    x = 2.5,
    y = 2.5,
    angle = 0,
    fov = math.rad(66),
    radius = 0.18,
    speed = 2.6,
    sprintSpeed = 3.75,
    turnSpeed = 2.55,
    bob = 0,
    moving = false,
  }

  local spawn = farthestCellFrom(2, 2)

  game.enemy = {
    x = spawn.x + 0.5,
    y = spawn.y + 0.5,
    radius = 0.2,
    baseSpeed = 1.32,
    sightSpeed = 1.72,
    path = {},
    pathTimer = 0,
    repathDelay = 0.22,
    visible = false,
    growl = 0,
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
  local distance = sqrt(dx * dx + dy * dy)

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

  dx, dy = player.x - enemy.x, player.y - enemy.y
  distance = sqrt(dx * dx + dy * dy)
  local caughtDistance = player.radius + enemy.radius + 0.12

  if distance < caughtDistance then
    game.state = "caught"
    game.bestTime = max(game.bestTime, game.survivalTime)
    love.mouse.setRelativeMode(false)
  end
end

local function drawBackground(width, height)
  local half = height / 2

  for y = 0, half, 6 do
    local t = y / half
    love.graphics.setColor(0.055 + t * 0.04, 0.058 + t * 0.045, 0.07 + t * 0.06)
    love.graphics.rectangle("fill", 0, y, width, 7)
  end

  for y = half, height, 6 do
    local t = (y - half) / half
    love.graphics.setColor(0.125 - t * 0.035, 0.115 - t * 0.035, 0.095 - t * 0.03)
    love.graphics.rectangle("fill", 0, y, width, 7)
  end

  love.graphics.setColor(0.18, 0.17, 0.15, 0.55)
  love.graphics.rectangle("fill", 0, half - 1, width, 2)
end

local function castRay(rayDirX, rayDirY)
  local player = game.player
  local mapX = floor(player.x)
  local mapY = floor(player.y)
  local deltaDistX = rayDirX == 0 and 1e30 or abs(1 / rayDirX)
  local deltaDistY = rayDirY == 0 and 1e30 or abs(1 / rayDirY)
  local stepX, stepY
  local sideDistX, sideDistY
  local side = 0

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

  for _ = 1, 128 do
    if sideDistX < sideDistY then
      sideDistX = sideDistX + deltaDistX
      mapX = mapX + stepX
      side = 0
    else
      sideDistY = sideDistY + deltaDistY
      mapY = mapY + stepY
      side = 1
    end

    if not isWalkableCell(mapX, mapY) then
      local distance

      if side == 0 then
        distance = (mapX - player.x + (1 - stepX) / 2) / rayDirX
      else
        distance = (mapY - player.y + (1 - stepY) / 2) / rayDirY
      end

      return max(distance, 0.01), side, mapX, mapY
    end
  end

  return wallRenderDistance, side, mapX, mapY
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
    local distance, side, mapX, mapY = castRay(rayDirX, rayDirY)
    local wallHeight = floor(height / distance)
    local drawStart = max(0, floor(height / 2 - wallHeight / 2))
    local drawEnd = min(height, floor(height / 2 + wallHeight / 2))
    local shade = clamp(1 - distance / wallRenderDistance, 0.14, 1)
    local brickTone = ((mapX * 13 + mapY * 17) % 7) / 7
    local sideShade = side == 1 and 0.76 or 1
    local red = (0.55 + brickTone * 0.08) * shade * sideShade
    local green = (0.50 + brickTone * 0.08) * shade * sideShade
    local blue = (0.43 + brickTone * 0.06) * shade * sideShade

    love.graphics.setColor(red, green, blue)
    love.graphics.rectangle("fill", screenX, drawStart, rayStep + 1, drawEnd - drawStart)

    if distance < 5 then
      love.graphics.setColor(red * 1.22, green * 1.17, blue * 1.12, 0.16)
      love.graphics.rectangle("fill", screenX, drawStart, rayStep + 1, 2)
    end

    for bufferX = screenX, min(screenX + rayStep, width - 1) do
      depthBuffer[bufferX + 1] = distance
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
  local spriteHeight = abs(floor(height / transformY))
  local spriteWidth = max(8, floor(spriteHeight * 0.46))
  local drawStartX = screenX - spriteWidth / 2
  local drawEndX = screenX + spriteWidth / 2

  if drawEndX < 0 or drawStartX > width then
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

  local bodyAlpha = clamp(1 - transformY / 26, 0.35, 1)
  local bodyWidth = spriteWidth
  local baseY = height / 2 + spriteHeight * 0.36
  local headY = -spriteHeight * 0.48
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
    -spriteHeight * 0.47,
    0,
    -spriteHeight * 0.7,
    bodyWidth * 0.23,
    -spriteHeight * 0.47,
    bodyWidth * 0.34,
    -spriteHeight * 0.04
  )

  love.graphics.setColor(0.45, 0.035, 0.03, bodyAlpha)
  love.graphics.polygon(
    "fill",
    -bodyWidth * 0.16,
    -spriteHeight * 0.1,
    -bodyWidth * 0.1,
    -spriteHeight * 0.45,
    0,
    -spriteHeight * 0.57,
    bodyWidth * 0.1,
    -spriteHeight * 0.45,
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

local function drawWeapon(width, height)
  local player = game.player
  local bob = sin(player.bob) * (player.moving and 7 or 2)
  local weaponX = width * 0.52
  local weaponY = height - 74 + bob

  love.graphics.setColor(0.035, 0.033, 0.03, 0.92)
  love.graphics.polygon(
    "fill",
    weaponX - 42,
    height,
    weaponX - 22,
    weaponY,
    weaponX + 42,
    weaponY,
    weaponX + 70,
    height
  )

  love.graphics.setColor(0.21, 0.18, 0.14, 0.94)
  love.graphics.rectangle("fill", weaponX - 26, weaponY - 14, 78, 24, 3, 3)

  love.graphics.setColor(0.08, 0.075, 0.065, 0.98)
  love.graphics.rectangle("fill", weaponX + 24, weaponY - 20, 44, 14, 2, 2)

  love.graphics.setColor(0.85, 0.55, 0.22, 0.22)
  love.graphics.circle("fill", weaponX + 72, weaponY - 13, 10)
end

local function drawMinimap(width, height)
  if not game.showMap then
    return
  end

  local maze = game.maze
  local size = min(width * 0.28 / maze.width, height * 0.34 / maze.height, 7)
  local mapWidth = maze.width * size
  local mapHeight = maze.height * size
  local originX = width - mapWidth - 18
  local originY = 18

  love.graphics.setColor(0, 0, 0, 0.42)
  love.graphics.rectangle("fill", originX - 7, originY - 7, mapWidth + 14, mapHeight + 14, 4, 4)

  for y = 1, maze.height do
    for x = 1, maze.width do
      if maze.grid[y][x] == 1 then
        love.graphics.setColor(0.52, 0.46, 0.38, 0.9)
      else
        love.graphics.setColor(0.11, 0.1, 0.085, 0.72)
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

  love.graphics.setColor(0.98, 0.86, 0.52, 0.95)
  love.graphics.circle("fill", px, py, max(2.5, size * 0.55))
  love.graphics.line(px, py, px + cos(player.angle) * size * 2.2, py + sin(player.angle) * size * 2.2)

  love.graphics.setColor(0.9, 0.08, 0.05, 0.95)
  love.graphics.circle("fill", ex, ey, max(2.5, size * 0.55))

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
  local distance = sqrt(dx * dx + dy * dy)
  local danger = clamp(1 - distance / 10, 0, 1)

  love.graphics.setFont(game.fonts.hud)
  love.graphics.setColor(0, 0, 0, 0.42)
  love.graphics.rectangle("fill", 18, 18, 204, 70, 4, 4)

  love.graphics.setColor(0.95, 0.88, 0.68)
  love.graphics.print(string.format("TIME  %05.1f", game.survivalTime), 30, 28)
  love.graphics.setColor(0.86 + danger * 0.14, 0.78 - danger * 0.48, 0.55 - danger * 0.45)
  love.graphics.print(string.format("THREAT %02dM", floor(distance)), 30, 55)

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
  drawWeapon(width, height)
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
