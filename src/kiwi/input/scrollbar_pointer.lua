-- Pointer routing for the renderer-neutral scrollback overlay. The host keeps
-- ownership of focus and coordinate conversion; this module only maps an
-- already pane-local event into a primary-screen history offset.
local Scrollbar = require("kiwi.renderer.scrollbar")

local Pointer = {}
Pointer.__index = Pointer

local function clamp(value, lower, upper)
  return math.max(lower, math.min(value, upper))
end

local function finite(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function normalized_pointer(event)
  if type(event) ~= "table" or not finite(event.pixel_x) or not finite(event.pixel_y)
    or not finite(event.pixel_width) or not finite(event.pixel_height)
    or event.pixel_width <= 0 or event.pixel_height <= 0 then
    return nil
  end
  return (event.pixel_x - 0.5) / event.pixel_width, clamp((event.pixel_y - 0.5) / event.pixel_height, 0, 1)
end

function Pointer.new()
  return setmetatable({ drag = nil }, Pointer)
end

function Pointer:reset()
  self.drag = nil
end

function Pointer:target_offset(descriptor, thumb_top)
  local travel = 1 - descriptor.thumb_size
  if descriptor.history_size < 1 or travel <= 0 then return 0 end
  local progress = clamp(thumb_top / travel, 0, 1)
  return math.floor((1 - progress) * descriptor.history_size + 0.5)
end

function Pointer:apply(state, descriptor, thumb_top)
  local target = self:target_offset(descriptor, thumb_top)
  if target == state.history_offset then return false end
  state:scroll_history(target - state.history_offset)
  return true
end

function Pointer:handle(event, state, descriptor)
  if self.drag ~= nil then
    if event.kind == "motion" then
      local _, y = normalized_pointer(event)
      if y == nil then return true, false end
      return true, self:apply(state, self.drag.descriptor, y - self.drag.grab_offset)
    end
    if event.kind == "button" and event.button == 0 and event.action == "release" then
      local _, y = normalized_pointer(event)
      local changed = y ~= nil and self:apply(state, self.drag.descriptor, y - self.drag.grab_offset) or false
      self:reset()
      return true, changed
    end
    return true, false
  end
  if type(descriptor) ~= "table" or not descriptor.active or event.kind ~= "button"
    or event.button ~= 0 or event.action ~= "press" then
    return false, false
  end
  local x, y = normalized_pointer(event)
  if x == nil then return false, false end
  local track_left = descriptor.left / state.columns
  local track_right = descriptor.right / state.columns
  if x < track_left or x > track_right then return false, false end
  local grab_offset = descriptor.thumb_size / 2
  if y >= descriptor.top and y <= descriptor.bottom then grab_offset = y - descriptor.top end
  self.drag = { descriptor = descriptor, grab_offset = grab_offset }
  return true, self:apply(state, descriptor, y - grab_offset)
end

function Pointer.descriptor(state, policy)
  return Scrollbar.descriptor(state, policy)
end

return Pointer
