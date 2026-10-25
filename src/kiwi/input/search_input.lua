-- Find owns its key presses and releases, independent of child keyboard modes.
local bit = require("bit")
local Keyboard = require("kiwi.input.keyboard")
local Input = {}
Input.__index = Input

function Input.new() return setmetatable({ held = {} }, Input) end
function Input:claim(key) self.held[key] = true end

function Input.editing(state)
  local view = state:search_view()
  return view.editing and view.visible
end

function Input.paste(state, clipboard)
  local remaining = state.search.maximum_query_bytes - #state.search.query
  if remaining <= 0 then return nil, "over-limit" end
  local text, status = clipboard:paste({ modes = {} }, remaining)
  if text == nil then return nil, status end
  return state:search_append(text)
end

function Input.text(state, codepoints)
  if not Input.editing(state) then return false end
  local text = Keyboard.text_sequence(codepoints, {})
  if text == nil then return true end
  local _, status = state:search_append(text)
  return true, status
end

function Input:key(state, key, action, modifiers, keys, clipboard)
  if action == keys.release and self.held[key] then
    self.held[key] = nil
    return { handled = true, suppress_text = false }
  end
  -- A fresh press replaces ownership left behind by a lost focus/release.
  if action == keys.press then self.held[key] = nil end
  local view = state:search_view()
  if action == keys.repeat_action and self.held[key] and not (view.editing and view.visible) then
    return { handled = true, suppress_text = true }
  end
  if not view.visible or not view.active then return nil end
  if not view.editing and key ~= keys.key_escape then return nil end
  if action == keys.release then return { handled = true, suppress_text = false } end
  self.held[key] = true
  local shift = bit.band(modifiers, keys.mod_shift) ~= 0
  local control = bit.band(modifiers, keys.mod_control) ~= 0
  local super = bit.band(modifiers, keys.mod_super) ~= 0
  local alt = bit.band(modifiers, keys.mod_alt) ~= 0
  local suppress, status, ignored = true
  if key == keys.key_escape then
    if action == keys.press then state:clear_search() end
  elseif key == keys.key_backspace then
    state:search_backspace()
  elseif key == string.byte("R") and alt and not control and not super then
    if action == keys.press then state:search_toggle_mode() end
  elseif key == keys.key_enter or key == keys.key_f3 or (key == string.byte("G") and super) then
    if action == keys.press then ignored, status = state:search_submit(shift and "backward" or nil) end
  elseif key == string.byte("V") and (super or (control and shift)) then
    if action == keys.press then ignored, status = Input.paste(state, clipboard) end
  else
    -- Text arrives through the host's character/IME callback. AltGr and Option
    -- must remain available for text entry even with report-all-keys enabled.
    suppress = super or (control and not alt)
  end
  return { handled = true, suppress_text = suppress }, status
end

return Input
