local Renderer = require("renderer.renderer")

local renderer

function love.load()
  renderer = assert(Renderer.new({ padding = 32 }))
  assert(renderer:load_font(love.graphics))
  assert(renderer:resize_window())
end

function love.resize()
  assert(renderer:resize_window())
end

function love.draw()
  assert(renderer:draw_empty())
end
