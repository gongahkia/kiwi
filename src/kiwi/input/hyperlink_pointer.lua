local bit = require("bit")

local HyperlinkPointer = {}
HyperlinkPointer.__index = HyperlinkPointer

local function application_mouse_enabled(modes)
  return modes and modes.mouse_sgr == true and (modes.mouse_tracking == "normal" or modes.mouse_tracking == "button" or modes.mouse_tracking == "any")
end

function HyperlinkPointer.new(activator, glfw)
  assert(type(activator) == "table" and type(activator.activate) == "function", "hyperlink pointer needs an activator")
  assert(type(glfw) == "table" and type(glfw.mod_control) == "number", "hyperlink pointer needs GLFW control modifier")
  return setmetatable({ activator = activator, control_modifier = glfw.mod_control }, HyperlinkPointer)
end

function HyperlinkPointer:handle(event, state, modes)
  if application_mouse_enabled(modes) then return false end
  if event.kind ~= "button" or event.button ~= 0 or event.action ~= "press" then return false end
  if bit.band(event.modifiers or 0, self.control_modifier) == 0 then return false end
  local link = state:hyperlink_at(event.selection_row, event.selection_column)
  if link == nil then return false end
  return true, self.activator:activate(link)
end

return HyperlinkPointer
