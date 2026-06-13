local CreatureContent = require("content.creatures")
local NPCContent = require("content.npcs")
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
  storm = 1.7,
  rubble = 1.45,
  slag = 1.35,
  ash = 1.25,
  bone = 1.15,
  organ = 1.2,
  signal = 0.9,
  moss = 0.75,
  dust = 0.85,
}

local function keyDown(game, action, fallback)
  if game and game.actionDown then
    return game.actionDown(action)
  end
  return fallback and love.keyboard.isDown(fallback)
end

local function firstGamepad()
  if not love.joystick or not love.joystick.getJoysticks then
    return nil
  end

  for _, joystick in ipairs(love.joystick.getJoysticks()) do
    if joystick:isGamepad() then
      return joystick
    end
  end

  return nil
end

local function axisValue(joystick, axis)
  if not joystick then
    return 0
  end

  local value = joystick:getGamepadAxis(axis) or 0
  if abs(value) < 0.18 then
    return 0
  end
  return value
end

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

  if Level.isHazardActive(cell) then
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

local creatureDefs = CreatureContent.defs
local predatorRank = CreatureContent.predatorRank
local toolAffinity = CreatureContent.toolAffinity
local signalAffinity = CreatureContent.signalAffinity
local coreCreatureKinds = { hunter = true, stalker = true, screecher = true, burrower = true }

function Actor.createCreature(level, kind, spawn, id)
  local deck = level.deck or 1
  local def = creatureDefs[kind] or creatureDefs.hunter
  local sx = spawn and spawn.x or level.start.x
  local sy = spawn and spawn.y or level.start.y
  local x, y = findSafeSpawn(level, sx, sy, def.radius)

  return {
    id = id or 1,
    kind = kind or "hunter",
    x = x,
    y = y,
    radius = def.radius,
    baseSpeed = def.baseSpeed + (deck - 1) * 0.08,
    sightSpeed = def.sightSpeed + (deck - 1) * 0.12,
    sight = def.sight,
    hearing = def.hearing,
    aggression = def.aggression,
    height = def.height,
    lethal = def.lethal,
    health = 1,
    path = {},
    pathTimer = 0,
    repathDelay = kind == "skitter" and 0.18 or 0.28,
    visible = false,
    growl = 0,
    eyeHeight = min(def.height - 0.08, 0.82),
    floorZ = Actor.floorAt(level, x, y),
    eyeZ = Actor.floorAt(level, x, y) + min(def.height - 0.08, 0.82),
    state = "wander",
    stateTimer = 0,
    grace = kind == "hunter" and max(2.9, 5.5 - (deck - 1) * 0.9) or (def.dormant and 5 or 1.2),
    lastKnownX = level.start.x + 0.5,
    lastKnownY = level.start.y + 0.5,
    targetKey = "",
    wanderTarget = nil,
    target = nil,
    homeRoom = spawn and spawn.room or nil,
    nest = spawn and spawn.nest or nil,
    faction = spawn and spawn.faction or (spawn and spawn.nest and spawn.nest.faction) or nil,
    territory = {
      centerX = (spawn and spawn.x or level.start.x) + 0.5,
      centerY = (spawn and spawn.y or level.start.y) + 0.5,
      radius = kind == "burrower" and 7 or (kind == "stalker" and 9 or 11),
    },
    memory = {},
    needs = { hunger = love.math.random(), fear = 0, curiosity = love.math.random() },
    traits = { sight = def.sight, hearing = def.hearing, aggression = def.aggression },
    modules = {
      senses = { sight = def.sight, hearing = def.hearing },
      territory = { loyalty = spawn and spawn.nest and 1 or 0.45, radius = kind == "burrower" and 7 or 10 },
      ecology = { curiosity = love.math.random(), fear = 0, hunger = love.math.random() },
    },
    guard = def.guard or false,
    aquatic = def.aquatic or false,
    dormant = def.dormant or false,
    flock = def.flock or false,
    thief = def.thief or false,
    alive = true,
    stealTimer = 0,
    trackTimer = love.math.random() * 1.4,
    carrying = nil,
    mood = "calm",
  }
end

function Actor.createEnemy(level)
  local spawn = Level.farthestCellFrom(level, level.start.x, level.start.y)
  return Actor.createCreature(level, "hunter", { x = spawn.x, y = spawn.y }, 1)
end

function Actor.createCreatures(level)
  local creatures = {}
  local wanted = { hunter = true, skitter = true }

  if (level.deck or 1) >= 2 then
    wanted.stalker = true
    wanted.burrower = true
  end
  if (level.deck or 1) >= 3 then
    wanted.screecher = true
  end

  for _, spawn in ipairs(level.creatureSpawns or {}) do
    if wanted[spawn.kind] or spawn.kind == "skitter" or (creatureDefs[spawn.kind] and not coreCreatureKinds[spawn.kind]) then
      creatures[#creatures + 1] = Actor.createCreature(level, spawn.kind, spawn, #creatures + 1)
      if spawn.kind ~= "skitter" then
        wanted[spawn.kind] = false
      end
    end
    if #creatures >= 3 + (level.deck or 1) then
      break
    end
  end

  for kind, needed in pairs(wanted) do
    if needed then
      local farthest = Level.farthestCellFrom(level, level.start.x, level.start.y)
      creatures[#creatures + 1] = Actor.createCreature(level, kind, { x = farthest.x, y = farthest.y }, #creatures + 1)
    end
  end

  return creatures
end

function Actor.createNPC(level, spawn, id)
  local kind = spawn and spawn.kind or NPCContent.order[((id or 1) - 1) % #NPCContent.order + 1]
  local profile = NPCContent.profiles[kind] or NPCContent.profiles.scout
  local x, y = findSafeSpawn(level, spawn and spawn.x or level.start.x, spawn and spawn.y or level.start.y, profile.radius or 0.16)
  local floorZ = Actor.floorAt(level, x, y)

  return {
    id = id or 1,
    kind = kind,
    name = profile.name or "Guide",
    callsign = profile.callsign or "GUIDE",
    title = profile.title or "guide",
    x = x,
    y = y,
    homeX = x,
    homeY = y,
    radius = profile.radius or 0.16,
    speed = profile.speed or 1,
    height = profile.height or 1.4,
    eyeHeight = min((profile.height or 1.4) - 0.1, 0.84),
    floorZ = floorZ,
    eyeZ = floorZ + min((profile.height or 1.4) - 0.1, 0.84),
    room = spawn and spawn.room or nil,
    path = {},
    pathTimer = 0,
    repathDelay = 0.42,
    targetKey = "",
    wanderTarget = nil,
    leadTarget = nil,
    state = "idle",
    stateTimer = 0,
    talking = false,
    color = profile.color,
    alive = true,
  }
end

function Actor.createNPCs(level)
  local npcs = {}

  for _, spawn in ipairs(level.npcSpawns or {}) do
    npcs[#npcs + 1] = Actor.createNPC(level, spawn, #npcs + 1)
  end

  return npcs
end

function Actor.emitNoise(game, x, y, intensity, ttl, kind)
  if intensity <= 0 then
    return
  end

  local event = {
    x = x,
    y = y,
    intensity = intensity,
    ttl = ttl or 0.7,
    radius = 4.5 + intensity * 2.1,
    kind = kind or "noise",
  }

  game.noises = game.noises or {}
  game.noises[#game.noises + 1] = event

  if not game.noise or intensity >= (game.noise.intensity or 0) or (game.noise.ttl or 0) <= 0 then
    game.noise = event
  end
end

function Actor.updatePlayer(game, dt, audio)
  local level = game.level
  local player = game.player
  local joystick = firstGamepad()
  local turn = 0

  if love.keyboard.isDown("left") or keyDown(game, "turnLeft", "q") then
    turn = turn - 1
  end

  if love.keyboard.isDown("right") or keyDown(game, "turnRight", "e") then
    turn = turn + 1
  end
  turn = turn + axisValue(joystick, "rightx")

  player.angle = player.angle + turn * player.turnSpeed * dt

  local forward = 0
  local strafe = 0

  if keyDown(game, "forward", "w") or love.keyboard.isDown("up") then
    forward = forward + 1
  end

  if keyDown(game, "back", "s") or love.keyboard.isDown("down") then
    forward = forward - 1
  end

  if keyDown(game, "strafeLeft", "a") then
    strafe = strafe - 1
  end

  if keyDown(game, "strafeRight", "d") then
    strafe = strafe + 1
  end

  forward = forward - axisValue(joystick, "lefty")
  strafe = strafe + axisValue(joystick, "leftx")

  local length = sqrt(forward * forward + strafe * strafe)
  player.moving = length > 0

  if length > 0 then
    forward = forward / length
    strafe = strafe / length
  end

  player.sprinting = forward > 0 and (keyDown(game, "sprint", "lshift") or love.keyboard.isDown("rshift") or (joystick and joystick:isGamepadDown("leftstick")))

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
    Actor.emitNoise(game, player.x, player.y, loudness, 0.7, "step")
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

local function setNPCState(npc, state, timer)
  if npc.state ~= state then
    npc.state = state
    npc.stateTimer = timer or 0
  elseif timer and (npc.stateTimer or 0) <= 0 then
    npc.stateTimer = timer
  end
end

local function npcReachableTarget(level, npc, x, y)
  local targetX = floor(x)
  local targetY = floor(y)

  if not Level.isWalkableCell(level, targetX, targetY) then
    return false
  end

  if floor(npc.x) == targetX and floor(npc.y) == targetY then
    return true
  end

  return #Level.findPath(level, floor(npc.x), floor(npc.y), targetX, targetY) > 0
end

local function nearestNPCThreat(game, npc)
  local nearest
  local nearestDistance = math.huge

  for _, creature in ipairs(game.creatures or {}) do
    if creature.alive and creature.lethal then
      local distance = distance2d(npc.x, npc.y, creature.x, creature.y)
      if distance < nearestDistance then
        nearest = creature
        nearestDistance = distance
      end
    end
  end

  return nearest, nearestDistance
end

local function npcFleeTarget(game, npc, threat)
  local level = game.level
  local awayX = npc.x - threat.x
  local awayY = npc.y - threat.y
  local length = sqrt(awayX * awayX + awayY * awayY)

  if length < 0.001 then
    awayX, awayY = 1, 0
    length = 1
  end

  awayX = awayX / length
  awayY = awayY / length

  for distance = 7, 2, -1 do
    local x = npc.x + awayX * distance
    local y = npc.y + awayY * distance
    if npcReachableTarget(level, npc, x, y) then
      return x, y
    end
  end

  return npc.homeX, npc.homeY
end

local function chooseNPCWanderTarget(level, npc)
  if npc.wanderTarget and distance2d(npc.x, npc.y, npc.wanderTarget.x, npc.wanderTarget.y) > 0.75 then
    return npc.wanderTarget.x, npc.wanderTarget.y
  end

  local room = npc.room
  for _ = 1, 12 do
    local x, y
    if room then
      x = love.math.random(room.x + 1, room.x + room.width - 2) + 0.5
      y = love.math.random(room.y + 1, room.y + room.height - 2) + 0.5
    else
      x = U.clamp(npc.homeX + love.math.random(-4, 4), 2, level.width - 1)
      y = U.clamp(npc.homeY + love.math.random(-4, 4), 2, level.height - 1)
    end

    if npcReachableTarget(level, npc, x, y) then
      npc.wanderTarget = { x = x, y = y }
      return x, y
    end
  end

  if distance2d(npc.x, npc.y, npc.homeX, npc.homeY) > 0.8 then
    npc.wanderTarget = { x = npc.homeX, y = npc.homeY }
    return npc.homeX, npc.homeY
  end

  return npc.x, npc.y
end

local function chooseNPCTarget(game, npc, dt)
  local threat, threatDistance = nearestNPCThreat(game, npc)
  npc.stateTimer = max(0, (npc.stateTimer or 0) - dt)

  if threat and (threatDistance < 6.2 or (threatDistance < 9.5 and Level.lineOfSight(game.level, npc.x, npc.y, threat.x, threat.y))) then
    npc.talking = false
    setNPCState(npc, "flee", 1.8)
    return npcFleeTarget(game, npc, threat)
  end

  if npc.talking then
    setNPCState(npc, "talk")
    return npc.x, npc.y
  end

  if npc.leadTarget then
    npc.leadTarget.ttl = max(0, (npc.leadTarget.ttl or 0) - dt)
    if npc.leadTarget.ttl > 0 and distance2d(npc.x, npc.y, npc.leadTarget.x, npc.leadTarget.y) > 1.4 then
      setNPCState(npc, "lead")
      return npc.leadTarget.x, npc.leadTarget.y
    end
    npc.leadTarget = nil
  end

  if distance2d(npc.x, npc.y, npc.homeX, npc.homeY) > 8 then
    setNPCState(npc, "return")
    npc.wanderTarget = { x = npc.homeX, y = npc.homeY }
    return npc.homeX, npc.homeY
  end

  setNPCState(npc, "wander")
  return chooseNPCWanderTarget(game.level, npc)
end

local function updateOneNPC(game, npc, dt)
  if not npc.alive then
    return
  end

  local level = game.level
  local targetX, targetY = chooseNPCTarget(game, npc, dt)

  if npc.state ~= "talk" then
    refreshEnemyPath(level, npc, targetX, targetY, dt)
    local waypoint = npc.path[1]

    if waypoint then
      targetX, targetY = waypoint.x, waypoint.y

      if distance2d(targetX, targetY, npc.x, npc.y) < 0.12 then
        table.remove(npc.path, 1)
        waypoint = npc.path[1]

        if waypoint then
          targetX, targetY = waypoint.x, waypoint.y
        end
      end
    end
  end

  local moveX, moveY = targetX - npc.x, targetY - npc.y
  local moveLength = sqrt(moveX * moveX + moveY * moveY)
  local stateSpeed = {
    idle = 0,
    talk = 0,
    wander = 0.58,
    lead = 0.98,
    flee = 1.28,
    ["return"] = 0.74,
  }
  local speed = (npc.speed or 1) * (stateSpeed[npc.state] or 0.6)

  if moveLength > 0.001 and speed > 0 then
    moveX = (moveX / moveLength) * speed * Actor.movementMultiplier(level, npc) * dt
    moveY = (moveY / moveLength) * speed * Actor.movementMultiplier(level, npc) * dt
    moveWithCollision(level, npc, moveX, moveY)
  end

  updateActorHeight(level, npc, dt)
end

function Actor.updateNPCs(game, dt)
  for _, npc in ipairs(game.npcs or {}) do
    updateOneNPC(game, npc, dt)
  end
end

local function strongestNoiseFor(creature, noises, game)
  local best
  local bestScore = 0

  for _, noise in ipairs(noises or {}) do
    if (noise.ttl or 0) > 0 then
      local distance = distance2d(creature.x, creature.y, noise.x, noise.y)
      if distance <= (noise.radius or 0) + (creature.hearing or 0) then
        local score = (noise.intensity or 0) * (1 - min(distance / max(1, (noise.radius or 1) + (creature.hearing or 0)), 0.95))
        if game and game.ecology and game.ecology.ventBloom > 0 then
          score = score * (creature.kind == "screecher" and 2.05 or 1.28)
        end
        if creature.kind == "screecher" then
          score = score * 1.8
        elseif creature.kind == "stalker" and noise.kind == "flare" then
          score = score * -2
        end
        if score > bestScore then
          best = noise
          bestScore = score
        end
      end
    end
  end

  return best, bestScore
end

local function lightPressure(game, creature)
  local level = game.level
  local cell = Level.cellAtWorld(level, creature.x, creature.y) or {}
  local systemBoost = level.systems and level.systems.lights and level.systems.lights.powered and 0.34 or 0
  local flareBoost = 0
  if game.ecology and game.ecology.blackout > 0 then
    systemBoost = systemBoost * 0.18
  end

  for _, effect in ipairs(game.effects or {}) do
    if effect.kind == "flare" and (effect.ttl or 0) > 0 then
      local distance = distance2d(creature.x, creature.y, effect.x, effect.y)
      if distance < (effect.radius or 0) then
        flareBoost = max(flareBoost, 1 - distance / effect.radius)
      end
    end
  end

  return U.clamp((cell.light or 0.45) + systemBoost + flareBoost, 0, 1.6)
end

local function factionHostility(level, a, b)
  if not a or not b or a == b then
    return a == b and -0.45 or 0
  end

  for _, faction in ipairs(level.factions or {}) do
    if faction.name == a then
      return faction.hostility and faction.hostility[b] or 0.55
    end
  end

  return 0.55
end

local function targetCreatureScore(level, creature, other, distance)
  if not other.alive or other == creature then
    return -math.huge
  end

  local myRank = predatorRank[creature.kind] or 1
  local theirRank = predatorRank[other.kind] or 1
  local factionPressure = factionHostility(level, creature.faction, other.faction)

  if creature.kind == "skitter" then
    return theirRank > myRank and 70 / max(distance, 0.6) or (-20 + factionPressure * 18)
  end

  if creature.kind == "burrower" then
    return distance < 5.5 and (44 + factionPressure * 24) / max(distance, 0.8) or -10
  end

  if theirRank < myRank then
    return ((creature.needs.hunger or 0.5) * 44 + factionPressure * 22) / max(distance, 0.8)
  end

  if theirRank > myRank then
    return -50 / max(distance, 0.8)
  end

  return (-8 + factionPressure * 18) / max(distance, 1)
end

function Actor.scorePropTarget(creature, prop)
  if not prop or (prop.ttl or 0) <= 0 then
    return -math.huge
  end

  local distance = distance2d(creature.x, creature.y, prop.x, prop.y)
  local affinity = toolAffinity[creature.kind] or {}
  local base = affinity[prop.kind] or 0

  if prop.kind == "snare" then
    base = creature.kind == "skitter" and 8 or 2
  end
  if prop.kind == "beacon" and creature.kind == "skitter" then
    base = base + 24
  end

  return base / max(distance, 0.8)
end

local function scoreSignalTarget(creature, signal)
  if not signal then
    return -math.huge
  end

  local affinity = signalAffinity[creature.kind] or {}
  local base = affinity[signal.kind] or 0
  if base == 0 then
    return -math.huge
  end

  local distance = distance2d(creature.x, creature.y, signal.x, signal.y)
  local ageModifier = signal.ttl and U.clamp(signal.ttl / 24, 0.2, 1) or 0.72
  if signal.source == creature.kind then
    base = base * 0.35
  elseif signal.source == "player" then
    base = base * 1.15
  end

  return base * (signal.strength or 1) * ageModifier / max(distance, 0.9)
end

local function scoreCacheTarget(creature, cache)
  if not creature.thief or not cache or not cache.cell or cache.cell.toolUsed or not cache.cell.tool then
    return -math.huge
  end

  local distance = distance2d(creature.x, creature.y, cache.x + 0.5, cache.y + 0.5)
  local value = (cache.cell.tool.salvage or 1) + (cache.cell.tool.mimic and -2 or 0)
  return (28 + value * 12) / max(distance, 0.8)
end

local function scoreInfrastructureTarget(level, creature, item)
  if not creature.guard or not item then
    return -math.huge
  end

  local x = (item.x or 0) + 0.5
  local y = (item.y or 0) + 0.5
  local distance = distance2d(creature.x, creature.y, x, y)
  local score = 22
  if item.cell and (item.cell.gateLocked or item.cell.lock) then
    score = score + 12
  end
  return score / max(distance, 0.8), x, y
end

local function chooseCreatureTarget(game, creature, dt)
  local level = game.level
  local player = game.player
  local best = nil
  local bestScore = -math.huge
  local playerDistance = distance2d(creature.x, creature.y, player.x, player.y)
  local light = lightPressure(game, creature)
  local sightRange = (creature.sight or 12) * (level.systems and level.systems.lights and level.systems.lights.powered and 1.35 or 1)
  local seesPlayer = creature.grace <= 0 and playerDistance <= sightRange and Level.lineOfSight(level, creature.x, creature.y, player.x, player.y)

  creature.grace = max(0, (creature.grace or 0) - dt)
  creature.stateTimer = max(0, (creature.stateTimer or 0) - dt)
  creature.growl = U.clamp((creature.growl or 0) - dt * 0.75, 0, 1)
  creature.needs.hunger = U.clamp((creature.needs.hunger or 0) + dt * 0.018, 0, 1)
  if creature.modules and creature.modules.ecology then
    creature.modules.ecology.hunger = creature.needs.hunger
  end
  creature.stealTimer = max(0, (creature.stealTimer or 0) - dt)
  creature.snared = max(0, (creature.snared or 0) - dt)

  if creature.dormant and not creature.awake then
    local surveyNear = game.survey and (game.survey.ttl or 0) > 0 and playerDistance < 12
    if playerDistance < 3.2 or surveyNear then
      creature.awake = true
      creature.dormant = false
      creature.grace = 0
      creature.growl = 1
    else
      setEnemyState(creature, "dormant")
      return creature.x, creature.y
    end
  end

  if creature.kind == "stalker" and light > 0.94 then
    best = { x = creature.x + (creature.x - player.x), y = creature.y + (creature.y - player.y), type = "flee" }
    bestScore = 100
  elseif creature.carrying and creature.nest then
    best = { x = creature.nest.x + 0.5, y = creature.nest.y + 0.5, type = "nest", nest = creature.nest }
    bestScore = 95
  elseif creature.kind == "skitter" then
    bestScore = -10
  end

  if seesPlayer and creature.kind ~= "skitter" then
    local score = 38 * (creature.aggression or 0.5) / max(playerDistance, 0.8)
    if creature.kind == "stalker" and light < 0.72 then
      score = score + 18
    elseif creature.kind == "screecher" then
      score = score * 0.45
    elseif creature.thief then
      score = -18 / max(playerDistance, 0.8)
    end
    if score > bestScore then
      best = creature.thief
        and { x = creature.x + (creature.x - player.x), y = creature.y + (creature.y - player.y), type = "flee" }
        or { x = player.x, y = player.y, type = "player" }
      bestScore = score
    end
  end

  local noise, noiseScore = strongestNoiseFor(creature, game.noises, game)
  if noise and noiseScore > bestScore then
    best = { x = noise.x, y = noise.y, type = "noise", kind = noise.kind }
    bestScore = noiseScore
  end

  for _, signal in ipairs(level.signals or {}) do
    local score = scoreSignalTarget(creature, signal)
    if score > bestScore then
      local flee = score < 0
      best = {
        x = flee and creature.x + (creature.x - signal.x) or signal.x,
        y = flee and creature.y + (creature.y - signal.y) or signal.y,
        type = flee and "flee" or "signal",
        signal = signal,
        kind = signal.kind,
      }
      bestScore = score
    end
  end

  for _, prop in ipairs(game.props or {}) do
    local score = Actor.scorePropTarget(creature, prop)
    if score > bestScore then
      local flee = score < 0
      best = {
        x = flee and creature.x + (creature.x - prop.x) or prop.x,
        y = flee and creature.y + (creature.y - prop.y) or prop.y,
        type = flee and "flee" or "prop",
        prop = prop,
        kind = prop.kind,
      }
      bestScore = score
    end
  end

  for _, cache in ipairs(level.toolCaches or {}) do
    local score = scoreCacheTarget(creature, cache)
    if score > bestScore then
      best = { x = cache.x + 0.5, y = cache.y + 0.5, type = "cache", cache = cache }
      bestScore = score
    end
  end

  for _, gate in ipairs(level.gates or {}) do
    local score, x, y = scoreInfrastructureTarget(level, creature, gate)
    if score > bestScore then
      best = { x = x, y = y, type = "guard", gate = gate }
      bestScore = score
    end
  end

  for _, other in ipairs(game.creatures or {}) do
    local distance = distance2d(creature.x, creature.y, other.x, other.y)
    if distance < 14 then
      local score = targetCreatureScore(level, creature, other, distance)
      if score > bestScore then
        local flee = score < 0 or (predatorRank[other.kind] or 0) > (predatorRank[creature.kind] or 0)
        best = {
          x = flee and creature.x + (creature.x - other.x) or other.x,
          y = flee and creature.y + (creature.y - other.y) or other.y,
          type = flee and "flee" or "creature",
          creature = other,
        }
        bestScore = score
      end
    end
  end

  if creature.kind == "burrower" and creature.homeRoom and playerDistance > 7 then
    best = best or { x = creature.homeRoom.cx + 0.5, y = creature.homeRoom.cy + 0.5, type = "home" }
  end

  if creature.target and creature.target.type == "nest" and (creature.stateTimer or 0) > 0 then
    best = best or creature.target
  end

  if best then
    creature.lastKnownX = best.x
    creature.lastKnownY = best.y
    creature.target = best
    creature.visible = best.type == "player"
    creature.growl = best.type == "player" and 1 or creature.growl
    if best.type == "flee" then
      setEnemyState(creature, "flee", 0.8)
    elseif best.type == "noise" then
      setEnemyState(creature, "investigate", 2.6)
    elseif best.type == "creature" or best.type == "prop" or best.type == "signal" or best.type == "cache" then
      setEnemyState(creature, "hunt", 1.4)
    elseif best.type == "guard" then
      setEnemyState(creature, "guard", 1.6)
    elseif best.type == "player" then
      setEnemyState(creature, "chase")
    else
      setEnemyState(creature, "wander")
    end
    return best.x, best.y
  end

  if (creature.state == "investigate" or creature.state == "search") and creature.stateTimer > 0 then
    return creature.lastKnownX, creature.lastKnownY
  end

  setEnemyState(creature, "wander")
  return chooseWanderTarget(level, creature)
end

local function updateOneCreature(game, creature, dt)
  if not creature.alive then
    return
  end

  local level = game.level
  local targetX, targetY = chooseCreatureTarget(game, creature, dt)

  if creature.state == "chase" and creature.visible then
    creature.path = {}
  else
    refreshEnemyPath(level, creature, targetX, targetY, dt)
    local waypoint = creature.path[1]

    if waypoint then
      targetX, targetY = waypoint.x, waypoint.y

      if distance2d(targetX, targetY, creature.x, creature.y) < 0.12 then
        table.remove(creature.path, 1)
        waypoint = creature.path[1]

        if waypoint then
          targetX, targetY = waypoint.x, waypoint.y
        end
      end
    end
  end

  local moveX, moveY = targetX - creature.x, targetY - creature.y
  local moveLength = sqrt(moveX * moveX + moveY * moveY)

  if moveLength > 0.001 then
    local keyProgress = game.keys and ((game.keys.collected or 0) / max(1, game.keys.total or 1)) or 0
    local escalation = keyProgress * 0.32 + ((game.deck or 1) - 1) * 0.12
    local stateSpeed = {
      wander = 0.78,
      investigate = 1.08,
      search = 1.16,
      hunt = 1.22,
      chase = 1.0,
      flee = 1.36,
      guard = 0.88,
      dormant = 0,
    }
    local playerDistance = distance2d(creature.x, creature.y, game.player.x, game.player.y)
    local base = creature.visible and creature.sightSpeed or creature.baseSpeed * (stateSpeed[creature.state] or 1)
    local pressure = U.clamp(1 - playerDistance / 18, 0, 0.35)
    local systemModifier = 1

    if creature.kind == "burrower" and game.level.systems and game.level.systems.pumps.powered then
      systemModifier = 0.58
    elseif creature.kind == "stalker" and lightPressure(game, creature) > 0.9 then
      systemModifier = 0.84
    end
    if game.ecology then
      local cyclePressure = (game.ecology.cycle and game.ecology.cycle.pressure) or 0
      systemModifier = systemModifier * (1 + cyclePressure * 0.08)
      if game.ecology.blackout > 0 and creature.kind == "stalker" then
        systemModifier = systemModifier * 1.22
      elseif game.ecology.flood > 0 and creature.kind == "burrower" then
        systemModifier = systemModifier * 1.18
      elseif game.ecology.heat > 0 and creature.kind == "skitter" then
        systemModifier = systemModifier * 1.2
      elseif game.ecology.nestWake > 0 and creature.nest then
        systemModifier = systemModifier * 1.12
      end
    end
    local cell = Level.cellAtWorld(level, creature.x, creature.y) or {}
    local biome = level.biomeProfile and level.biomeProfile.district
    if biome == "waste_artery" and cell.terrain == "sludge" and creature.kind == "burrower" then
      systemModifier = systemModifier * 1.28
    elseif biome == "cryo_vault" and cell.terrain == "ice" and creature.kind == "stalker" then
      systemModifier = systemModifier * 1.16
    elseif (biome == "reactor_trench" or biome == "ash_foundry") and creature.kind == "screecher" then
      systemModifier = systemModifier * 1.12
    end
    if (creature.snared or 0) > 0 then
      systemModifier = systemModifier * 0.35
    end

    moveX = (moveX / moveLength) * (base + pressure + escalation) * systemModifier * Actor.movementMultiplier(level, creature) * dt
    moveY = (moveY / moveLength) * (base + pressure + escalation) * systemModifier * Actor.movementMultiplier(level, creature) * dt
    moveWithCollision(level, creature, moveX, moveY)
  end

  updateActorHeight(level, creature, dt)
end

local function handleCreaturePropContact(game, creature)
  if not creature.alive then
    return
  end

  for _, prop in ipairs(game.props or {}) do
    if (prop.ttl or 0) > 0 and distance2d(creature.x, creature.y, prop.x, prop.y) < creature.radius + 0.35 then
      if prop.kind == "snare" and prop.armed then
        prop.armed = false
        prop.ttl = 0.8
        creature.snared = 2.8
        creature.stateTimer = max(creature.stateTimer or 0, 2.4)
        creature.mood = "fleeing"
        Actor.emitNoise(game, prop.x, prop.y, 2.9, 1.2, "snare")
      elseif creature.kind == "skitter" and not creature.carrying and (prop.kind == "scent" or prop.kind == "noisemaker" or prop.kind == "probe" or prop.kind == "beacon") then
        creature.carrying = { kind = prop.kind, source = "prop" }
        prop.ttl = 0
        setEnemyState(creature, "flee", 2.4)
      elseif prop.kind == "pheromone" then
        if creature.kind == "hunter" or creature.kind == "stalker" then
          setEnemyState(creature, "flee", 1.7)
          creature.mood = "wary"
        elseif creature.kind == "burrower" then
          creature.mood = "guarding"
          setEnemyState(creature, "hunt", 1.4)
        end
      elseif prop.kind == "probe" and creature.kind == "skitter" and not creature.carrying then
        creature.carrying = { kind = "probe", source = "prop" }
        prop.ttl = 0
        setEnemyState(creature, "flee", 2)
      end
    end
  end
end

local function handleCreatureCacheContact(game, creature)
  if not creature.alive or not creature.thief then
    return
  end

  for _, cache in ipairs(game.level.toolCaches or {}) do
    if cache.cell and cache.cell.tool and not cache.cell.toolUsed and distance2d(creature.x, creature.y, cache.x + 0.5, cache.y + 0.5) < creature.radius + 0.42 then
      cache.cell.toolUsed = true
      cache.cell.salvage = false
      creature.carrying = { kind = cache.cell.tool.kind, source = "cache" }
      creature.stealTimer = 8
      setEnemyState(creature, "flee", 2.6)
      Actor.emitNoise(game, cache.x + 0.5, cache.y + 0.5, 2.2, 1.2, "theft")
      return
    end
  end
end

local function handleNestBehavior(game, creature, dt)
  if not creature.alive or not creature.nest then
    return
  end

  local nest = creature.nest
  local distance = distance2d(creature.x, creature.y, nest.x + 0.5, nest.y + 0.5)
  nest.alarm = max(0, (nest.alarm or 0) - dt)

  if creature.carrying and distance < 1.2 then
    nest.hoard[#nest.hoard + 1] = creature.carrying
    creature.carrying = nil
    creature.needs.hunger = U.clamp((creature.needs.hunger or 0.5) - 0.18, 0, 1)
  end

  if distance < 5.5 and creature.kind == nest.kind and nest.alarm > 0 then
    creature.mood = "guarding"
    setEnemyState(creature, "hunt", 1.2)
  end
end

local function updateNestRaids(game, dt)
  for _, nest in ipairs(game.level.nests or {}) do
    nest.raidTimer = max(0, (nest.raidTimer or 0) - dt)
    if nest.raidTimer <= 0 then
      nest.raidTimer = 12 + love.math.random() * 16
      for _, creature in ipairs(game.creatures or {}) do
        if creature.alive and predatorRank[creature.kind] and creature.kind ~= nest.kind then
          local rankDelta = (predatorRank[creature.kind] or 0) - (predatorRank[nest.kind] or 0)
          local factionPressure = factionHostility(game.level, creature.faction, nest.faction)
          local distance = distance2d(creature.x, creature.y, nest.x + 0.5, nest.y + 0.5)
          if (rankDelta > 0 or factionPressure > 0.75) and distance < 13 then
            creature.target = { x = nest.x + 0.5, y = nest.y + 0.5, type = "nest", nest = nest }
            setEnemyState(creature, "hunt", 2.6)
            nest.alarm = 7
            Actor.emitNoise(game, nest.x + 0.5, nest.y + 0.5, 2.6, 1.5, "raid")
            break
          end
        end
      end
    end
  end
end

local function resolveCreatureContacts(game)
  local player = game.player

  for _, creature in ipairs(game.creatures or {}) do
    if creature.alive then
      handleCreaturePropContact(game, creature)
      handleCreatureCacheContact(game, creature)
      handleNestBehavior(game, creature, 0)
      local distance = distance2d(player.x, player.y, creature.x, creature.y)
      if (creature.kind == "skitter" or creature.thief) and distance < player.radius + creature.radius + 0.16 and creature.stealTimer <= 0 then
        local inventory = game.inventory or {}
        local stolen
        for _, tool in ipairs({ "oil", "flare", "probe", "pheromone", "noisemaker", "scent", "snare", "beacon" }) do
          if (inventory[tool] or 0) > 0 then
            inventory[tool] = inventory[tool] - 1
            stolen = tool
            creature.carrying = { kind = tool, source = "player" }
            break
          end
        end
        creature.stealTimer = 8
        setEnemyState(creature, "flee", 2)
        Actor.emitNoise(game, creature.x, creature.y, 2.4, 1.2, "panic")
        if game.setMessage and stolen then
          game.setMessage("SKITTER STOLE " .. string.upper(stolen), 1.6)
        end
      elseif creature.lethal and creature.grace <= 0 and distance < player.radius + creature.radius + 0.12 then
        if game.resetLife then
          game.resetLife("CAUGHT")
        else
          game.state = "caught"
          game.bestTime = max(game.bestTime, game.survivalTime)
          love.mouse.setRelativeMode(false)
        end
      end
    end
  end

  for i, creature in ipairs(game.creatures or {}) do
    if creature.alive then
      for j = i + 1, #(game.creatures or {}) do
        local other = game.creatures[j]
        if other.alive and distance2d(creature.x, creature.y, other.x, other.y) < creature.radius + other.radius + 0.2 then
          local aRank = predatorRank[creature.kind] or 1
          local bRank = predatorRank[other.kind] or 1
          if aRank > bRank and other.kind == "skitter" then
            other.alive = false
            Actor.emitNoise(game, other.x, other.y, 2.8, 1.4, "panic")
          elseif bRank > aRank and creature.kind == "skitter" then
            creature.alive = false
            Actor.emitNoise(game, creature.x, creature.y, 2.8, 1.4, "panic")
          else
            setEnemyState(creature, "flee", 0.7)
            setEnemyState(other, "flee", 0.7)
          end
        end
      end
    end
  end
end

function Actor.nearestThreat(game)
  local nearest
  local nearestDistance = math.huge

  for _, creature in ipairs(game.creatures or {}) do
    if creature.alive and creature.kind ~= "skitter" then
      local distance = distance2d(game.player.x, game.player.y, creature.x, creature.y)
      if distance < nearestDistance then
        nearest = creature
        nearestDistance = distance
      end
    end
  end

  return nearest or (game.creatures and game.creatures[1]), nearestDistance
end

function Actor.updateCreatures(game, dt, audio)
  updateNestRaids(game, dt)
  for _, creature in ipairs(game.creatures or {}) do
    updateOneCreature(game, creature, dt)
    handleNestBehavior(game, creature, dt)
  end

  resolveCreatureContacts(game)
  game.enemy = Actor.nearestThreat(game) or game.enemy

  if audio and game.enemy then
    audio.enemy(game.enemy, game.player, dt)
  end
end

function Actor.updateEnemy(game, dt, audio)
  if game.creatures then
    Actor.updateCreatures(game, dt, audio)
    return
  end

  game.creatures = { game.enemy }
  Actor.updateCreatures(game, dt, audio)
end

return Actor
