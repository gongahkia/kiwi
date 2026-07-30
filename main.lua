package.path = table.concat({
  "src/?.lua",
  "src/?/init.lua",
  package.path,
}, ";")

local Standalone = require("app.standalone")

local standalone

function love.load()
  standalone = assert(Standalone.from_love(love.graphics, { padding = 32 }))
end

function love.resize()
  assert(standalone:resize_window())
end

function love.update(seconds)
  assert(standalone:update(seconds))
end

function love.draw()
  assert(standalone:draw())
end

function love.quit()
  assert(standalone:stop())
end
