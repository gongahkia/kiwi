local app = require("src.app.app")

local application

function love.load(args)
  application = app.new(args or {})
  application:load()
end

function love.update(delta_time)
  application:update(delta_time)
end

function love.draw()
  application:draw()
end

function love.keypressed(key)
  application:keypressed(key)
end
