local Game = require("game")
local smoke = false

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

function love.load()
  smoke = hasArg("--smoke")
  Game.load()
end

function love.update(dt)
  if not smoke then
    Game.update(dt)
  end
end

function love.draw()
  Game.draw()
  if smoke then
    print("ok love smoke")
    love.event.quit(0)
  end
end

function love.keypressed(key)
  Game.keypressed(key)
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
