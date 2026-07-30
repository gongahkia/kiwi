local scene_manager = {}
local manager = {}
manager.__index = manager

local function validate_scene(scene)
  if type(scene) ~= "table" then
    return nil, { code = "invalid_scene", message = "scene must be a table" }
  end
  return true
end

function scene_manager.new(initial_scene)
  local valid, err = validate_scene(initial_scene)
  if not valid then
    return nil, err
  end
  local instance = setmetatable({ current = nil }, manager)
  local replaced, replace_err = instance:replace(initial_scene)
  if not replaced then
    return nil, replace_err
  end
  return instance
end

function manager:replace(next_scene)
  local valid, err = validate_scene(next_scene)
  if not valid then
    return nil, err
  end
  if self.current and self.current.leave then
    self.current:leave(next_scene)
  end
  local previous = self.current
  self.current = next_scene
  if next_scene.enter then
    next_scene:enter(previous)
  end
  return true
end

function manager:update(delta_time)
  if self.current.update then
    self.current:update(delta_time)
  end
end

function manager:draw()
  if self.current.draw then
    self.current:draw()
  end
end

function manager:keypressed(key)
  if self.current.keypressed then
    self.current:keypressed(key)
  end
end

return scene_manager
