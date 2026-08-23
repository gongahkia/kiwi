-- Maps host wheel deltas to primary-screen history navigation without
-- interfering with terminal mouse reporting or alternate-screen scroll mode.
local Wheel = {}
Wheel.__index = Wheel

Wheel.maximum_lines_per_event = 16

local function finite_number(value)
  return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Wheel.new()
  return setmetatable({ remainder = 0 }, Wheel)
end

function Wheel:reset()
  self.remainder = 0
end

function Wheel:consume(event, modes)
  if type(event) ~= "table" or type(modes) ~= "table"
    or modes.alternate_screen == true or modes.mouse_tracking ~= "none" then
    self:reset()
    return nil
  end
  local delta = event.delta
  if not finite_number(delta) or delta == 0 then return nil end
  delta = math.max(-Wheel.maximum_lines_per_event, math.min(Wheel.maximum_lines_per_event, delta))
  if self.remainder ~= 0 and (self.remainder > 0) ~= (delta > 0) then self:reset() end
  self.remainder = self.remainder + delta
  local lines = math.floor(math.abs(self.remainder))
  if lines == 0 then return nil end
  local direction = self.remainder < 0 and -1 or 1
  self.remainder = self.remainder - direction * lines
  return direction * lines
end

return Wheel
