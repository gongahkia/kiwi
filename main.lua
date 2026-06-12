local Game = require("game")
local Actor = require("actor")
local Level = require("level")
local smoke = false
local validate = false
local demo = false

local function hasArg(value)
  if not arg then
    return false
  end

  for _, item in ipairs(arg) do
    if item == value then
      return true
    end
  end

  return false
end

local function argValue(prefix)
  if not arg then
    return nil
  end

  for _, item in ipairs(arg) do
    local value = item:match("^" .. prefix .. "=(%d+)$")
    if value then
      return tonumber(value)
    end
  end

  return nil
end

local function runValidation()
  local count = argValue("%-%-validate") or 100
  if hasArg("--validate-fast") then
    count = 50
  elseif hasArg("--validate-deep") then
    count = 1000
  end
  local failed = 0
  local function validationBranch(seed, deck)
    local order = Level.biomeOrder or {}
    local biome = order[((seed + deck - 2) % #order) + 1]
    local profile = Level.biomeProfiles[biome]
    return {
      kind = (seed + deck) % 3 == 0 and "conflict" or ((seed + deck) % 2 == 0 and "salvage" or "safe"),
      biome = biome,
      risk = ((seed + deck) % 3) + 1,
      salvage = ((seed + deck + 1) % 3) + 1,
      faction = profile and profile.primaryFaction or "scavenger",
      incident = profile and profile.incidents[((seed + deck - 1) % #profile.incidents) + 1] or nil,
    }
  end

  for seed = 1, count do
    for deck = 1, Level.maxDecks do
      love.math.setRandomSeed(seed + deck * 1000003)
      local level = Level.generate(nil, nil, deck, validationBranch(seed, deck))
      local validation = Level.validate(level)
      if not validation.valid then
        failed = failed + 1
        print(string.format("fail seed=%d deck=%d %s", seed, deck, table.concat(validation.failures, ",")))
      end
    end
  end

  if failed > 0 then
    print(string.format("failed %d checks", failed))
    love.event.quit(1)
  else
    print(string.format("ok %d seeds x %d decks mode=love", count, Level.maxDecks))
    love.event.quit(0)
  end
end

local function runSmoke()
  love.math.setRandomSeed(1001)
  local level = Level.generate(nil, nil, 1)
  local validation = Level.validate(level)
  local player = Actor.createPlayer(level)
  local creatures = Actor.createCreatures(level)

  if not validation.valid then
    print("fail love smoke " .. table.concat(validation.failures, ","))
    love.event.quit(1)
    return
  end
  if not Actor.canOccupy(level, player) then
    print("fail love smoke player-spawn")
    love.event.quit(1)
    return
  end
  for _, creature in ipairs(creatures) do
    if not Actor.canOccupy(level, creature) then
      print("fail love smoke creature-" .. (creature.kind or "unknown"))
      love.event.quit(1)
      return
    end
  end

  print("ok love smoke")
  love.event.quit(0)
end

function love.load()
  smoke = hasArg("--smoke")
  validate = hasArg("--validate") or hasArg("--validate-fast") or hasArg("--validate-deep") or argValue("%-%-validate") ~= nil
  demo = hasArg("--demo")
  if smoke then
    runSmoke()
    return
  end
  if validate then
    runValidation()
    return
  end
  Game.setDemoMode(demo)
  Game.load()
end

function love.update(dt)
  if validate or smoke then
    return
  end

  Game.update(dt)
end

function love.draw()
  if validate or smoke then
    return
  end

  Game.draw()
end

function love.keypressed(key)
  Game.keypressed(key)
end

function love.keyreleased(key)
  if Game.keyreleased then
    Game.keyreleased(key)
  end
end

function love.textinput(text)
  Game.textinput(text)
end

function love.mousepressed(...)
  Game.mousepressed(...)
end

function love.mousemoved(...)
  Game.mousemoved(...)
end

function love.gamepadpressed(...)
  Game.gamepadpressed(...)
end

function love.gamepadreleased(...)
  if Game.gamepadreleased then
    Game.gamepadreleased(...)
  end
end
