local bit = require("bit")
local Input = {}
Input.__index = Input
function Input.new() return setmetatable({ held = {} }, Input) end
function Input.activate(state, clipboard, hyperlink, override)
  local link, action = state.hints:target(state)
  if not link then return nil, action end
  action = override or action
  local ok, status
  if action == "copy" then
    if clipboard then ok, status = clipboard:copy_text(link.uri) else status = "clipboard-unavailable" end
  elseif hyperlink then ok, status = hyperlink:activate(link)
  else status = "opener-unavailable" end
  if ok then state.hints:clear(action == "copy" and "copied" or "opened")
  else state.hints.status = status or "unavailable" end
  return ok, status
end
function Input.commit(state, text)
  if not state.hints or not state.hints.active then return false end
  state.hints:append(state, text)
  return true
end
function Input:key(state, key, action, modifiers, keys, clipboard, hyperlink)
  if action == keys.release and self.held[key] then
    self.held[key] = nil; return { handled = true, suppress_text = false }
  end
  if action == keys.press then self.held[key] = nil end
  if not state.hints or not state.hints.active then
    if action == keys.repeat_action and self.held[key] then return { handled = true, suppress_text = true } end
    return nil
  end
  if action == keys.release then return { handled = true, suppress_text = false } end
  self.held[key] = true
  state.hints:reconcile(state)
  local control, shift = bit.band(modifiers, keys.mod_control) ~= 0, bit.band(modifiers, keys.mod_shift) ~= 0
  local super, alt = bit.band(modifiers, keys.mod_super) ~= 0, bit.band(modifiers, keys.mod_alt) ~= 0
  local suppress = true
  if key == keys.key_escape or (key == string.byte("C") and control and not shift) then state.hints:clear()
  elseif key == keys.key_enter then
    if action == keys.press then Input.activate(state, clipboard, hyperlink) end
  elseif key == string.byte("C") and (super or control and shift) then
    if action == keys.press then Input.activate(state, clipboard, hyperlink, "copy") end
  elseif key == keys.key_backspace then state.hints:backspace()
  elseif key == keys.key_page_down or key == keys.key_page_up then state.hints:next_page(key == keys.key_page_up and -1 or 1)
  elseif key == keys.key_tab or key == keys.key_up or key == keys.key_down then
    local labels, current = state.hints:labels(state), nil
    for index, label in ipairs(labels) do if label.index == state.hints.selected then current = index end end
    if #labels > 0 then
      local direction = (key == keys.key_up or shift) and -1 or 1
      local index = current and (current - 1 + direction) % #labels + 1 or (direction > 0 and 1 or #labels)
      state.hints.selected = labels[index].index
      state.hints:changed()
    end
  elseif key == string.byte("R") and control and not alt and not super then
    if action == keys.press then state:hints_begin(state.hints.action) end
  else suppress = super or (control and not alt) end
  return { handled = true, suppress_text = suppress }
end
return Input
