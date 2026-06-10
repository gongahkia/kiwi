local Actor = require("actor")
local Audio = require("audio")
local Level = require("level")
local Renderer = require("renderer")
local UI = require("ui")
local U = require("utils")

local floor = math.floor
local max = math.max

local Game = {
  level = nil,
  player = nil,
  enemy = nil,
  showMap = false,
  state = "playing",
  survivalTime = 0,
  bestTime = 0,
  seed = 0,
  lastSeed = 0,
  deck = 1,
  maxDecks = Level.maxDecks,
  fonts = {},
  objectives = { total = 0, collected = 0 },
  keys = { total = 0, collected = 0 },
  torch = { fuel = 1 },
  noise = { ttl = 0, intensity = 0, radius = 0, x = 0, y = 0 },
  message = "",
  messageTimer = 0,
  hazardTimer = 0,
  seedEntry = { active = false, text = "" },
}

local function newSeed()
  return os.time() + floor(love.timer.getTime() * 1000)
end

local function setMessage(text, duration)
  Game.message = text
  Game.messageTimer = duration or 2
end

local function deckSeed(seed, deck)
  return seed + deck * 1000003
end

local function startDeck(deck)
  Game.deck = deck
  love.math.setRandomSeed(deckSeed(Game.seed, deck))

  Game.level = Level.generate(nil, nil, deck)
  Game.player = Actor.createPlayer(Game.level)
  Game.enemy = Actor.createEnemy(Game.level)
  Game.state = "playing"
  Game.objectives = { total = #Game.level.objectives, collected = 0 }
  Game.keys = { total = #Game.level.keys, collected = 0 }
  Game.noise = { ttl = 0, intensity = 0, radius = 0, x = 0, y = 0 }
  Game.hazardTimer = 0
  Game.seedEntry.active = false
  Game.seedEntry.text = ""
  setMessage(string.format("DECK %02d", Game.deck), 1.5)
  love.mouse.setRelativeMode(true)
end

local function startGame(seed)
  Game.seed = seed or newSeed()
  Game.lastSeed = Game.seed
  Game.deck = 1
  Game.survivalTime = 0
  Game.torch = { fuel = 1 }
  startDeck(1)
end

local function advanceDeck()
  if Game.deck >= Game.maxDecks then
    Game.state = "escaped"
    Game.bestTime = max(Game.bestTime, Game.survivalTime)
    love.mouse.setRelativeMode(false)
    return
  end

  startDeck(Game.deck + 1)
end

local function updateNoise(dt)
  if Game.noise.ttl and Game.noise.ttl > 0 then
    Game.noise.ttl = max(0, Game.noise.ttl - dt)
    Game.noise.intensity = Game.noise.intensity * (1 - U.clamp(dt * 2.4, 0, 1))
    if Game.noise.ttl <= 0 then
      Game.noise.intensity = 0
    end
  end
end

local function updateTorch(dt)
  local drain = 0.010

  if Game.player.sprinting then
    drain = drain + 0.004
  end

  if Game.enemy.visible then
    drain = drain + 0.002
  end

  Game.torch.fuel = U.clamp(Game.torch.fuel - dt * drain, 0, 1)
end

local function updateHazards(dt)
  Game.hazardTimer = max(0, (Game.hazardTimer or 0) - dt)

  local cell = Level.cellAtWorld(Game.level, Game.player.x, Game.player.y)
  if not cell or not cell.hazard or not cell.hazard.active then
    return
  end

  local drain = cell.hazard.kind == "ember" and 0.055 or (cell.hazard.kind == "wire" and 0.038 or 0.026)
  Game.torch.fuel = U.clamp(Game.torch.fuel - dt * drain, 0, 1)

  if Game.hazardTimer <= 0 then
    setMessage(string.upper(cell.hazard.kind), 1.1)
    Game.hazardTimer = 2.4
  end
end

local function checkInteractions()
  local cell = Level.cellAtWorld(Game.level, Game.player.x, Game.player.y)

  if not cell then
    return
  end

  if cell.objective and not cell.objective.collected then
    cell.objective.collected = true
    Game.objectives.collected = Game.objectives.collected + 1
    Audio.relay()
    setMessage(cell.objective.label .. " ONLINE", 2.2)

    if Game.objectives.collected >= Game.objectives.total then
      Level.setGatesLocked(Game.level, false)
      Level.activateDynamics(Game.level, "relays")
      setMessage("ALL RELAYS ONLINE - EXIT SHAFT OPEN", 3)
    end
  end

  if cell.key and not cell.key.collected then
    cell.key.collected = true
    Game.keys.collected = Game.keys.collected + 1
    Level.setLocksLocked(Game.level, false)
    Audio.refill()
    setMessage("KEY", 1.6)
  end

  if cell.refill and not cell.refillUsed then
    cell.refillUsed = true
    Game.torch.fuel = U.clamp(Game.torch.fuel + 0.42, 0, 1)
    Audio.refill()
    setMessage("OIL CACHE", 1.8)
  end

  if Game.objectives.collected >= Game.objectives.total
    and cell.exit then
    advanceDeck()
  end
end

function Game.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  Game.fonts.hud = love.graphics.newFont(17)
  Game.fonts.title = love.graphics.newFont(58)
  Renderer.init()
  Audio.init()
  startGame()
end

function Game.update(dt)
  dt = math.min(dt, 1 / 30)

  if Game.messageTimer > 0 then
    Game.messageTimer = max(0, Game.messageTimer - dt)
  end

  Audio.update(Game, dt)

  if Game.state == "playing" and not Game.seedEntry.active then
    Game.survivalTime = Game.survivalTime + dt
    updateNoise(dt)
    Actor.updatePlayer(Game, dt, Audio)
    updateTorch(dt)
    updateHazards(dt)
    checkInteractions()
    Actor.updateEnemy(Game, dt, Audio)
  end
end

function Game.draw()
  Renderer.draw(Game)
  UI.draw(Game)
end

function Game.keypressed(key)
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

  if key == "escape" then
    love.mouse.setRelativeMode(not love.mouse.getRelativeMode())
  elseif key == "m" then
    Game.showMap = not Game.showMap
  elseif key == "r" or (key == "space" and Game.state ~= "playing") then
    startGame(Game.lastSeed)
  elseif key == "n" then
    startGame()
  elseif key == "f2" then
    Game.seedEntry.active = true
    Game.seedEntry.text = tostring(Game.seed)
    love.mouse.setRelativeMode(false)
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

function Game.mousepressed()
  if Game.state == "playing" and not Game.seedEntry.active then
    love.mouse.setRelativeMode(true)
  end
end

function Game.mousemoved(_, _, dx)
  if love.mouse.getRelativeMode() and Game.state == "playing" and not Game.seedEntry.active then
    Game.player.angle = Game.player.angle + dx * 0.0024
  end
end

return Game
