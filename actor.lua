local Level = require("level")
local U = require("utils")

local floor = math.floor
local ceil = math.ceil
local abs = math.abs
local max = math.max
local min = math.min
local sqrt = math.sqrt
local cos = math.cos
local sin = math.sin

local Actor = {
  eyeHeight = 0.72,
  playerHeight = 1.55,
}

local terrainNoise = {
  grate = 1.8,
  catwalk = 1.65,
  water = 1.6,
  rubble = 1.45,
  slag = 1.35,
  moss = 0.75,
  dust = 0.85,
}

local function canStandAt(level, x, y, radius)
  local centerX = floor(x)
  local centerY = floor(y)
  local centerCell = Level.cellAtCell(level, centerX, centerY)
  local margin = radius + 0.015
  local samples = {
    { x, y },
    { x - margin, y },
    { x + margin, y },
    { x, y - margin },
    { x, y + margin },
    { x - margin, y - margin },
    { x + margin, y - margin },
    { x - margin, y + margin },
    { x + margin, y + margin },
  }

  if Level.isBlocked(centerCell) then
    return false
  end

  for _, sample in ipairs(samples) do
    local targetX = floor(sample[1])
    local targetY = floor(sample[2])

    if Level.isBlocked(Level.cellAtWorld(level, sample[1], sample[2])) then
      return false
    end

    if not Level.canTraverseCells(level, centerX, centerY, targetX, targetY) then
      return false
    end
  end

  return true
end

local function findSafeSpawn(level, startX, startY, radius)
  if canStandAt(level, startX + 0.5, startY + 0.5, radius) then
    return startX + 0.5, startY + 0.5
  end

  for range = 1, max(level.width, level.height) do
    for y = max(2, startY - range), min(level.height - 1, startY + range) do
      for x = max(2, startX - range), min(level.width - 1, startX + range) do
        if abs(x - startX) + abs(y - startY) == range and canStandAt(level, x + 0.5, y + 0.5, radius) then
          return x + 0.5, y + 0.5
        end
      end
    end
  end

  return startX + 0.5, startY + 0.5
end

function Actor.floorAt(level, worldX, worldY)
  local cell = Level.cellAtWorld(level, worldX, worldY)
  if cell and not Level.isBlocked(cell) then
    return cell.floor
  end
  return 0
end

local function canOccupyFrom(level, entity, x, y, radius)
  local fromX = floor(entity.x)
  local fromY = floor(entity.y)
  local centerX = floor(x)
  local centerY = floor(y)
  local fromCell = Level.cellAtCell(level, fromX, fromY)
  local centerCell = Level.cellAtCell(level, centerX, centerY)
  local margin = radius + 0.015
  local ladderMove = fromCell
    and centerCell
    and fromCell.ladder
    and centerCell.ladder
    and Level.canTraverseCells(level, fromX, fromY, centerX, centerY)
  local samples = {
    { x, y },
    { x - margin, y },
    { x + margin, y },
    { x, y - margin },
    { x, y + margin },
    { x - margin, y - margin },
    { x + margin, y - margin },
    { x - margin, y + margin },
    { x + margin, y + margin },
  }

  if Level.isBlocked(fromCell) or Level.isBlocked(centerCell) then
    return false
  end

  if not ladderMove and not Level.canTraverseCells(level, fromX, fromY, centerX, centerY) then
    return false
  end

  for _, sample in ipairs(samples) do
    local targetX = floor(sample[1])
    local targetY = floor(sample[2])

    if Level.isBlocked(Level.cellAtWorld(level, sample[1], sample[2])) then
      return false
    end

    if not Level.canTraverseCells(level, centerX, centerY, targetX, targetY) then
      return false
    end
  end

  return true
end

function Actor.canOccupy(level, entity, x, y)
  return canOccupyFrom(level, entity, x or entity.x, y or entity.y, entity.radius)
end

function Actor.movementMultiplier(level, actor)
  local cell = Level.cellAtWorld(level, actor.x, actor.y)

  if not cell or Level.isBlocked(cell) then
    return 1
  end

  if cell.hazard and cell.hazard.active then
    if cell.hazard.kind == "pit" then
      return 0.56
    elseif cell.hazard.kind == "ember" then
      return 0.72
    elseif cell.hazard.kind == "wire" then
      return 0.82
    end
  end

  if cell.ladder then
    return Level.terrainSpeed.ladder
  end

  return Level.terrainSpeed[cell.terrain] or 1
end

local function moveWithCollision(level, entity, dx, dy)
  local steps = max(1, ceil(max(abs(dx), abs(dy)) / 0.08))
  local stepX = dx / steps
  local stepY = dy / steps

  for _ = 1, steps do
    if canOccupyFrom(level, entity, entity.x + stepX, entity.y, entity.radius) then
      entity.x = entity.x + stepX
    end

    if canOccupyFrom(level, entity, entity.x, entity.y + stepY, entity.radius) then
      entity.y = entity.y + stepY
    end
  end
end

local function updateActorHeight(level, actor, dt)
  local targetFloor = Actor.floorAt(level, actor.x, actor.y)
  local cell = Level.cellAtWorld(level, actor.x, actor.y)
  actor.floorZ = actor.floorZ or targetFloor
  actor.climbing = cell and cell.ladder and abs((actor.floorZ or targetFloor) - targetFloor) > 0.04

  local climbRate = actor.climbing and 3.35 or 12
  actor.floorZ = U.mix(actor.floorZ, targetFloor, U.clamp(dt * climbRate, 0, 1))
  actor.eyeZ = actor.floorZ + (actor.eyeHeight or Actor.eyeHeight)
end

function Actor.createPlayer(level)
  local x, y = findSafeSpawn(level, level.start.x, level.start.y, 0.18)
  local player = {
    x = x,
    y = y,
    angle = 0,
    fov = math.rad(66),
    radius = 0.18,
    speed = 2.62,
    sprintSpeed = 3.75,
    turnSpeed = 2.55,
    bob = 0,
    moving = false,
    sprinting = false,
    eyeHeight = Actor.eyeHeight,
    floorZ = 0,
    eyeZ = Actor.eyeHeight,
    stepTimer = 0,
  }

  updateActorHeight(level, player, 1)
  return player
end

function Actor.createEnemy(level)
  local spawn = Level.farthestCellFrom(level, level.start.x, level.start.y)
  local x, y = findSafeSpawn(level, spawn.x, spawn.y, 0.2)
  local deck = level.deck or 1

  return {
    x = x,
    y = y,
    radius = 0.2,
    baseSpeed = 1.18 + (deck - 1) * 0.11,
    sightSpeed = 1.68 + (deck - 1) * 0.16,
    path = {},
    pathTimer = 0,
    repathDelay = 0.24,
    visible = false,
    growl = 0,
    eyeHeight = 0.82,
    floorZ = Actor.floorAt(level, x, y),
    eyeZ = Actor.floorAt(level, x, y) + 0.82,
    state = "wander",
    stateTimer = 0,
    grace = max(2.9, 5.5 - (deck - 1) * 0.9),
    lastKnownX = level.start.x + 0.5,
    lastKnownY = level.start.y + 0.5,
    targetKey = "",
    wanderTarget = nil,
  }
end

local function emitNoise(game, x, y, intensity, ttl)
  if intensity <= 0 then
    return
  end

  if not game.noise or intensity >= (game.noise.intensity or 0) or (game.noise.ttl or 0) <= 0 then
    game.noise = {
      x = x,
      y = y,
      intensity = intensity,
      ttl = ttl or 0.7,
      radius = 4.5 + intensity * 2.1,
    }
  end
end

function Actor.updatePlayer(game, dt, audio)
  local level = game.level
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

  player.sprinting = forward > 0 and (love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift"))

  local speed = (player.sprinting and player.sprintSpeed or player.speed) * Actor.movementMultiplier(level, player)
  local dirX, dirY = cos(player.angle), sin(player.angle)
  local strafeX, strafeY = -dirY, dirX
  local dx = (dirX * forward + strafeX * strafe) * speed * dt
  local dy = (dirY * forward + strafeY * strafe) * speed * dt

  moveWithCollision(level, player, dx, dy)
  updateActorHeight(level, player, dt)

  if player.moving then
    player.bob = player.bob + dt * (player.sprinting and 12 or 8)
    player.stepTimer = player.stepTimer - dt * (player.sprinting and 1.4 or 1)
  else
    player.bob = player.bob + dt * 2
    player.stepTimer = min(player.stepTimer, 0.08)
  end

  if player.moving and player.stepTimer <= 0 then
    local cell = Level.cellAtWorld(level, player.x, player.y) or {}
    local terrain = cell.ladder and "ladder" or (cell.terrain or "stone")
    local loudness = (terrainNoise[terrain] or 1) * (player.sprinting and 1.8 or 1)

    player.stepTimer = player.sprinting and 0.28 or 0.42
    emitNoise(game, player.x, player.y, loudness, 0.7)
    if audio then
      audio.step(terrain, player.sprinting)
    end
  end
end

local function setEnemyState(enemy, state, timer)
  if enemy.state ~= state then
    enemy.state = state
    enemy.stateTimer = timer or 0
  elseif timer and enemy.stateTimer <= 0 then
    enemy.stateTimer = timer
  end
end

local function distance2d(ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  return sqrt(dx * dx + dy * dy)
end

local function chooseWanderTarget(level, enemy)
  if enemy.wanderTarget and distance2d(enemy.x, enemy.y, enemy.wanderTarget.x, enemy.wanderTarget.y) > 0.6 then
    return enemy.wanderTarget.x, enemy.wanderTarget.y
  end

  for _ = 1, 12 do
    local room = level.rooms[love.math.random(#level.rooms)]
    if Level.isWalkableCell(level, room.cx, room.cy) then
      enemy.wanderTarget = { x = room.cx + 0.5, y = room.cy + 0.5 }
      return enemy.wanderTarget.x, enemy.wanderTarget.y
    end
  end

  enemy.wanderTarget = { x = enemy.x, y = enemy.y }
  return enemy.x, enemy.y
end

local function updateEnemyState(game, dt, distance)
  local level = game.level
  local enemy = game.enemy
  local player = game.player
  local wasChasing = enemy.state == "chase"
  local noise = game.noise or { ttl = 0 }

  enemy.grace = max(0, (enemy.grace or 0) - dt)
  enemy.stateTimer = max(0, (enemy.stateTimer or 0) - dt)
  enemy.visible = enemy.grace <= 0 and distance < 24 and Level.lineOfSight(level, enemy.x, enemy.y, player.x, player.y)
  enemy.growl = U.clamp(enemy.growl - dt * 0.75, 0, 1)

  if enemy.visible then
    enemy.lastKnownX = player.x
    enemy.lastKnownY = player.y
    enemy.growl = 1
    setEnemyState(enemy, "chase")
    return player.x, player.y
  end

  if wasChasing then
    setEnemyState(enemy, "search", 3.8)
    return enemy.lastKnownX, enemy.lastKnownY
  end

  if noise.ttl and noise.ttl > 0 and enemy.grace <= 0 then
    local noiseDistance = distance2d(enemy.x, enemy.y, noise.x, noise.y)
    if noiseDistance <= (noise.radius or 0) then
      enemy.lastKnownX = noise.x
      enemy.lastKnownY = noise.y
      setEnemyState(enemy, "investigate", 3.5)
      return noise.x, noise.y
    end
  end

  if enemy.state == "investigate" and enemy.stateTimer > 0 then
    return enemy.lastKnownX, enemy.lastKnownY
  end

  if enemy.state == "search" and enemy.stateTimer > 0 then
    return enemy.lastKnownX, enemy.lastKnownY
  end

  if game.objectives.collected > 0 and enemy.grace <= 0 then
    setEnemyState(enemy, "hunt", 1.4)
    return player.x, player.y
  end

  setEnemyState(enemy, "wander")
  return chooseWanderTarget(level, enemy)
end

local function refreshEnemyPath(level, enemy, targetX, targetY, dt)
  local targetCellX = floor(targetX)
  local targetCellY = floor(targetY)
  local targetKey = U.keyOf(targetCellX, targetCellY)

  enemy.pathTimer = enemy.pathTimer - dt

  if enemy.pathTimer <= 0 or enemy.targetKey ~= targetKey then
    enemy.path = Level.findPath(level, floor(enemy.x), floor(enemy.y), targetCellX, targetCellY)
    enemy.pathTimer = enemy.repathDelay
    enemy.targetKey = targetKey
  end
end

function Actor.updateEnemy(game, dt, audio)
  local level = game.level
  local enemy = game.enemy
  local player = game.player
  local dx, dy = player.x - enemy.x, player.y - enemy.y
  local z = (player.floorZ or 0) - (enemy.floorZ or 0)
  local distance = sqrt(dx * dx + dy * dy + z * z * 0.35)
  local targetX, targetY = updateEnemyState(game, dt, distance)

  if enemy.state == "chase" and enemy.visible then
    enemy.path = {}
  else
    refreshEnemyPath(level, enemy, targetX, targetY, dt)
    local waypoint = enemy.path[1]

    if waypoint then
      targetX, targetY = waypoint.x, waypoint.y

      if distance2d(targetX, targetY, enemy.x, enemy.y) < 0.12 then
        table.remove(enemy.path, 1)
        waypoint = enemy.path[1]

        if waypoint then
          targetX, targetY = waypoint.x, waypoint.y
        end
      end
    end
  end

  local moveX, moveY = targetX - enemy.x, targetY - enemy.y
  local moveLength = sqrt(moveX * moveX + moveY * moveY)

  if moveLength > 0.001 then
    local escalation = (game.objectives.collected / max(1, game.objectives.total)) * 0.42 + ((game.deck or 1) - 1) * 0.12
    local stateSpeed = {
      wander = 0.78,
      investigate = 1.08,
      search = 1.16,
      hunt = 1.22,
      chase = 1.0,
    }
    local base = enemy.visible and enemy.sightSpeed or enemy.baseSpeed * (stateSpeed[enemy.state] or 1)
    local pressure = U.clamp(1 - distance / 18, 0, 0.35)

    moveX = (moveX / moveLength) * (base + pressure + escalation) * Actor.movementMultiplier(level, enemy) * dt
    moveY = (moveY / moveLength) * (base + pressure + escalation) * Actor.movementMultiplier(level, enemy) * dt
    moveWithCollision(level, enemy, moveX, moveY)
  end

  updateActorHeight(level, enemy, dt)

  dx, dy = player.x - enemy.x, player.y - enemy.y
  z = (player.floorZ or 0) - (enemy.floorZ or 0)
  distance = sqrt(dx * dx + dy * dy + z * z * 0.35)
  local caughtDistance = player.radius + enemy.radius + 0.12

  if enemy.grace <= 0 and distance < caughtDistance then
    game.state = "caught"
    game.bestTime = max(game.bestTime, game.survivalTime)
    love.mouse.setRelativeMode(false)
  end

  if audio then
    audio.enemy(enemy, player, dt)
  end
end

return Actor
