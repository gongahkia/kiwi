local Renderer = require("renderer.renderer")
local Terminal = require("terminal.terminal")

local renderer
local terminal

function love.load()
  renderer = assert(Renderer.new({ padding = 32 }))
  assert(renderer:load_font(love.graphics))
  local _, resize_event = assert(renderer:resize_window())
  terminal = assert(Terminal.new({ columns = resize_event.columns, rows = resize_event.rows }))
end

function love.resize()
  local _, resize_event = assert(renderer:resize_window())
  if resize_event then
    assert(terminal:resize(resize_event.columns, resize_event.rows))
  end
end

function love.draw()
  assert(renderer:draw_terminal(terminal))
end
