-- GLFW reports physical key and Unicode text events separately. This small
-- adapter holds at most one key until the current event turn ends so Kitty
-- associated-text reports can retain every text codepoint without guessing a
-- layout mapping.
local Correlation = {}
Correlation.__index = Correlation

function Correlation.new(emit)
  assert(type(emit) == "function", "input correlation needs an emit callback")
  return setmetatable({ emit = emit, pending = nil }, Correlation)
end

function Correlation:flush()
  local pending = self.pending
  if pending == nil then return false end
  self.pending = nil
  self.emit(pending.codepoints, pending.event)
  return true
end

function Correlation:defer(event)
  assert(type(event) == "table", "input correlation event must be a table")
  self:flush()
  self.pending = { event = event, codepoints = {} }
end

function Correlation:text(codepoint)
  assert(type(codepoint) == "number" and codepoint % 1 == 0 and codepoint >= 0 and codepoint <= 0x10ffff, "input correlation codepoint is invalid")
  if self.pending == nil then return false end
  self.pending.codepoints[#self.pending.codepoints + 1] = codepoint
  return true
end

return Correlation
