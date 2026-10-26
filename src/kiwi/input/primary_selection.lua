local Clipboard = require("kiwi.input.clipboard")
local Pointer = require("kiwi.input.selection_pointer")
local Primary = {}
Primary.__index = Primary
function Primary.new(bridge)
  return setmetatable({ bridge = bridge, maximum_bytes = Clipboard.maximum_bytes, status = "inactive" }, Primary)
end
function Primary:supported(enabled)
  return enabled ~= false and self.bridge.primary_supported and self.bridge:primary_supported()
end
function Primary:cancel()
  -- Finish the already-sent conversion without delivering it. Destroying its
  -- X window while a local owner is replying can raise BadWindow in that owner.
  if self.request then self.cancelled = true end
  self.next_target = nil
  self.target, self.selecting = nil, nil
end
function Primary:destroy()
  self:cancel()
  if self.request then
    if self.request.retire then self.request:retire() else self.request:destroy() end
    self.request = nil
  end
end
function Primary:start(state)
  self.request, self.status = self.bridge:primary_read(self.maximum_bytes)
  self.cancelled = false
  if self.request then
    self.target, self.scope = state, state:selection_scope()
    self.bracketed = state.modes.bracketed_paste
    self.status = "pending"
  end
end
function Primary:publish(state, enabled)
  if not self:supported(enabled) then return false, "unavailable" end
  local text, status = state:selection_text(self.maximum_bytes)
  if text == nil or text == "" then return false, status or "empty" end
  if not Clipboard.valid_utf8(text) then return false, "invalid-utf8" end
  local written
  written, status = self.bridge:primary_write(text)
  self.status = written and "published" or status or "platform-error"
  return written, self.status
end
function Primary:selection(event, state, handled, enabled)
  if event.kind ~= "button" or event.button ~= 0 then return end
  if event.action == "press" then self.selecting = handled and state or nil
  elseif event.action == "release" then
    local publish = self.selecting == state
    self.selecting = nil
    if publish then return self:publish(state, enabled) end
  end
end
function Primary:button(event, state, enabled, mouse_shift_capture)
  if event.kind ~= "button" or event.button ~= 2 then return false end
  if event.action == "release" and self.middle_owned then self.middle_owned = nil; return true end
  if event.action == "press" then self.middle_owned = nil end
  if event.action ~= "press" or not self:supported(enabled)
      or Pointer.application_captures(event, state:input_modes(), mouse_shift_capture) then return false end
  self.middle_owned = true
  self:cancel()
  if self.request then
    self.next_target = { state = state, scope = state:selection_scope(), bracketed = state.modes.bracketed_paste }
  else self:start(state) end
  return true
end
function Primary:poll(state, enabled)
  if not self.request then return nil end
  if not self.cancelled and (not self:supported(enabled) or self.target ~= state or self.scope ~= state:selection_scope()
      or self.bracketed ~= state.modes.bracketed_paste
      or state.vi.active or state.hints.active or state:search_view().editing) then
    self:cancel()
  end
  local text, status = self.request:poll()
  if status == "pending" then return nil end
  self.request:destroy(); self.request = nil
  local cancelled, next_target = self.cancelled, self.next_target
  self:cancel()
  if cancelled then
    self.status = "cancelled"
    if next_target and next_target.state == state and next_target.scope == state:selection_scope()
        and next_target.bracketed == state.modes.bracketed_paste and self:supported(enabled)
        and not state.vi.active and not state.hints.active and not state:search_view().editing then self:start(state) end
    return nil
  end
  if text ~= nil then text, status = Clipboard.prepare_paste(text, state.modes, self.maximum_bytes) end
  self.status = status
  return text, status
end
return Primary
