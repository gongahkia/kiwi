local CreatureContent = require("content.creatures")
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

local creatureDefs = {
  hunter = { radius = 0.2, baseSpeed = 1.18, sightSpeed = 1.68, sight = 24, hearing = 10, aggression = 1, height = 1.55, lethal = true },
  stalker = { radius = 0.18, baseSpeed = 1.02, sightSpeed = 1.92, sight = 18, hearing = 7, aggression = 0.72, height = 1.35, lethal = true },
  skitter = { radius = 0.14, baseSpeed = 1.34, sightSpeed = 1.72, sight = 12, hearing = 9, aggression = 0.1, height = 0.55, lethal = false },
  screecher = { radius = 0.18, baseSpeed = 0.95, sightSpeed = 1.52, sight = 6, hearing = 18, aggression = 0.86, height = 1.18, lethal = true },
  burrower = { radius = 0.22, baseSpeed = 0.78, sightSpeed = 1.18, sight = 10, hearing = 8, aggression = 0.62, height = 0.85, lethal = true },
}

local predatorRank = {
  skitter = 0,
  stalker = 1,
  screecher = 2,
  burrower = 2,
  hunter = 3,
}

local toolAffinity = {
  hunter = { bait = 24, scent = 34, sonic = 18, noisemaker = 22, flare = 10, pheromone = -38, probe = 8 },
  stalker = { bait = 14, scent = 28, sonic = 10, noisemaker = 15, flare = -55, flash = -60, pheromone = -30, probe = 12 },
  skitter = { bait = 36, scent = 18, sonic = 18, noisemaker = 10, flash = -60, pheromone = 14, probe = 32 },
  screecher = { bait = 8, scent = 8, sonic = 58, noisemaker = 44, flare = 8, pheromone = -8, probe = 20 },
  burrower = { bait = 18, scent = 10, sonic = 8, noisemaker = 12, pheromone = 30, probe = 4 },
}

local signalAffinity = {
  hunter = { track = 28, scratch = 22, scent_trail = 30, nest_debris = 14, wet_tracks = 8, ash_drift = -4, vent_call = 14, alarm_mark = 22, pheromone = -34, survey_ping = 8, dark_pulse = 10, frost_trace = 8, spore_bloom = 20, pressure_tick = 18, radiant_heat = 6, tainted_sludge = 12 },
  stalker = { track = 24, scratch = 30, scent_trail = 26, nest_debris = 8, wet_tracks = 4, ash_drift = 4, vent_call = 8, alarm_mark = 18, pheromone = -28, survey_ping = 12, dark_pulse = 36, frost_trace = 24, spore_bloom = 12, pressure_tick = 14, radiant_heat = -6, tainted_sludge = 4 },
  skitter = { track = -16, scratch = -18, scent_trail = 12, nest_debris = 32, wet_tracks = 8, ash_drift = -8, vent_call = -8, alarm_mark = -20, pheromone = 12, survey_ping = 24, dark_pulse = 4, frost_trace = -12, spore_bloom = 28, pressure_tick = -8, radiant_heat = -16, tainted_sludge = 22 },
  screecher = { track = 6, scratch = 8, scent_trail = 4, nest_debris = 10, wet_tracks = 8, ash_drift = 8, vent_call = 34, alarm_mark = 26, pheromone = -10, survey_ping = 18, dark_pulse = 4, frost_trace = 2, spore_bloom = 8, pressure_tick = 18, radiant_heat = 26, tainted_sludge = 4 },
  burrower = { track = 10, scratch = 18, scent_trail = 6, nest_debris = 24, wet_tracks = 30, ash_drift = -12, vent_call = 4, alarm_mark = 18, pheromone = 28, survey_ping = 4, dark_pulse = 2, frost_trace = -10, spore_bloom = 18, pressure_tick = 4, radiant_heat = -8, tainted_sludge = 34 },
}

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
    grace = kind == "hunter" and max(2.9, 5.5 - (deck - 1) * 0.9) or 1.2,
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
  local wanted = { hunter = true, stalker = true, skitter = true }

  if (level.deck or 1) >= 2 then
    wanted.screecher = true
  end
  if (level.deck or 1) >= 3 then
    wanted.burrower = true
  end

  for _, spawn in ipairs(level.creatureSpawns or {}) do
    if wanted[spawn.kind] or spawn.kind == "skitter" then
      creatures[#creatures + 1] = Actor.createCreature(level, spawn.kind, spawn, #creatures + 1)
      if spawn.kind ~= "skitter" then
        wanted[spawn.kind] = false
      end
    end
    if #creatures >= 4 + (level.deck or 1) then
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
    if (effect.kind == "flare" or effect.kind == "flash") and (effect.ttl or 0) > 0 then
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

  if prop.kind == "bait" and creature.kind ~= "skitter" then
    base = base * (0.55 + (creature.needs.hunger or 0.5))
  end
  if prop.kind == "snare" then
    base = creature.kind == "skitter" and 8 or 2
  end
  if creature.nest and prop.kind == "bait" and distance2d(prop.x, prop.y, creature.nest.x + 0.5, creature.nest.y + 0.5) < 4 then
    base = creature.kind == creature.nest.kind and -45 or base + 12
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
    end
    if game.recordCodexDiscovery then
      game.recordCodexDiscovery("creature", creature.kind, (creature.kind or "creature") .. " has directly tracked you by sight.")
    end
    if score > bestScore then
      best = { x = player.x, y = player.y, type = "player" }
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
    elseif best.type == "creature" or best.type == "prop" or best.type == "signal" then
      setEnemyState(creature, "hunt", 1.4)
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
    local escalation = (game.objectives.collected / max(1, game.objectives.total)) * 0.42 + ((game.deck or 1) - 1) * 0.12
    local stateSpeed = {
      wander = 0.78,
      investigate = 1.08,
      search = 1.16,
      hunt = 1.22,
      chase = 1.0,
      flee = 1.36,
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
    elseif biome == "reactor_trench" and creature.kind == "screecher" then
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
        if game.recordCodexDiscovery then
          game.recordCodexDiscovery("tool", "snare", "Snare wires slow the first creature that crosses them, then break loudly.")
        end
      elseif prop.kind == "flash" and prop.armed then
        prop.armed = false
        prop.ttl = 0.9
        if creature.kind == "stalker" or creature.kind == "skitter" then
          setEnemyState(creature, "flee", 2.2)
        else
          creature.grace = max(creature.grace or 0, 1.4)
        end
        Actor.emitNoise(game, prop.x, prop.y, 2.1, 0.8, "flash")
        if game.recordCodexDiscovery then
          game.recordCodexDiscovery("tool", "flash", "Flash pods scatter skitters and stalkers and briefly break hunter sight pressure.")
        end
      elseif creature.kind == "skitter" and not creature.carrying and (prop.kind == "bait" or prop.kind == "scent" or prop.kind == "sonic") then
        creature.carrying = { kind = prop.kind, source = "prop" }
        prop.ttl = 0
        setEnemyState(creature, "flee", 2.4)
        if game.recordCodexDiscovery then
          game.recordCodexDiscovery("creature", "skitter_hoard", "Skitters steal useful objects and drag them back to hoards.")
        end
      elseif prop.kind == "bait" and creature.kind ~= "skitter" then
        prop.ttl = 0
        creature.needs.hunger = U.clamp((creature.needs.hunger or 0.5) - 0.45, 0, 1)
      elseif prop.kind == "pheromone" then
        if creature.kind == "hunter" or creature.kind == "stalker" then
          setEnemyState(creature, "flee", 1.7)
          creature.mood = "wary"
        elseif creature.kind == "burrower" then
          creature.mood = "guarding"
          setEnemyState(creature, "hunt", 1.4)
        end
        if game.recordCodexDiscovery then
          game.recordCodexDiscovery("tool", "pheromone", "Pheromone boundaries make predators hesitate and territorial creatures investigate.")
        end
      elseif prop.kind == "probe" and creature.kind == "skitter" and not creature.carrying then
        creature.carrying = { kind = "probe", source = "prop" }
        prop.ttl = 0
        setEnemyState(creature, "flee", 2)
      end
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
            if game.recordCodexDiscovery then
              game.recordCodexDiscovery("nest", nest.kind, "Predators raid weaker nests when they catch a scent or hear panic.")
            end
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
      handleNestBehavior(game, creature, 0)
      local distance = distance2d(player.x, player.y, creature.x, creature.y)
      if creature.kind == "skitter" and distance < player.radius + creature.radius + 0.16 and creature.stealTimer <= 0 then
        local inventory = game.inventory or {}
        local stolen
        for _, tool in ipairs({ "oil", "flare", "probe", "pheromone", "noisemaker", "fuse", "seal", "breaker" }) do
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
        game.state = "caught"
        game.bestTime = max(game.bestTime, game.survivalTime)
        love.mouse.setRelativeMode(false)
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
