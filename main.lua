local Game = require("game")

function love.load()
  Game.load()
end

function love.update(dt)
  Game.update(dt)
end

function love.draw()
  Game.draw()
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
