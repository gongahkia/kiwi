local scene_manager = require("src.app.scene_manager")
local source_loader = require("src.dsl.source_loader")

local app = {}
app.__index = app

local function has_argument(arguments, expected)
  for _, argument in ipairs(arguments) do
    if argument == expected then
      return true
    end
  end
  return false
end

local function splash_scene()
  return {
    draw = function()
      love.graphics.clear(0.04, 0.05, 0.07, 1)
      love.graphics.setColor(0.75, 0.87, 0.92, 1)
      love.graphics.printf("Doctrine", 0, 220, love.graphics.getWidth(), "center")
      love.graphics.setColor(0.5, 0.62, 0.68, 1)
      love.graphics.printf("Milestone 0", 0, 250, love.graphics.getWidth(), "center")
    end,
  }
end

function app.new(arguments)
  local manager = assert(scene_manager.new(splash_scene()))
  return setmetatable({
    scene_manager = manager,
    smoke = has_argument(arguments, "--smoke"),
    doctrine_source = nil,
    source_error = nil,
  }, app)
end

function app:load()
  local source, err = source_loader.load(source_loader.DEFAULT_FIXTURE, function(path)
    return love.filesystem.read(path)
  end)
  self.doctrine_source = source
  self.source_error = err
end

function app:update(delta_time)
  self.scene_manager:update(delta_time)
  if self.smoke then
    self.smoke = false
    love.event.quit(0)
  end
end

function app:draw()
  self.scene_manager:draw()
end

function app:keypressed(key)
  if key == "escape" then
    love.event.quit(0)
    return
  end
  self.scene_manager:keypressed(key)
end

return app
