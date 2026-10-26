local Clipboard = require("kiwi.input.clipboard")
local Pointer = require("kiwi.input.selection_pointer")
local SearchInput = require("kiwi.input.search_input")
local Primary = {}
Primary.__index = Primary
local function destination(state) return SearchInput.editing(state) and "search" or "terminal" end
local function same_input(state, kind, query, bracketed)
  if state.hints.active then return false end
  if SearchInput.editing(state) then return kind == "search" and query == state.search.query end
  return kind == "terminal" and not state.vi.active and bracketed == state.modes.bracketed_paste
end
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
  self.destination, self.query = destination(state), state.search.query
  self.read_limit = self.destination == "search" and math.min(self.maximum_bytes, state.search.maximum_query_bytes - #self.query) or self.maximum_bytes
  if self.read_limit <= 0 then self.status = "over-limit"; return end
  self.request, self.status = self.bridge:primary_read(self.read_limit)
  self.cancelled = false
  if self.request then
    self.target, self.scope = state, state:selection_scope()
    self.bracketed = state.modes.bracketed_paste
    self.status = "pending"
  end
end
function Primary:paste(state, enabled)
  if not self:supported(enabled) then return nil, "unavailable" end
  if state.hints.active or (state.vi.active and not SearchInput.editing(state)) then return nil, "input-mode-active" end
  self:queue_paste(state)
  return self.request ~= nil, self.status
end
function Primary:queue_paste(state)
  self:cancel()
  if self.request then
    self.next_target = { state = state, scope = state:selection_scope(), bracketed = state.modes.bracketed_paste,
      destination = destination(state), query = state.search.query }
  else self:start(state) end
end
function Primary:focus(state)
  self.keyboard_state = state
  self.keyboard_revision = state.vi.primary_revision or 0
end
function Primary:sync_keyboard(state, enabled)
  if self.keyboard_state ~= state then self:focus(state); return end
  local vi = state.vi
  local revision = vi.primary_revision or 0
  if revision == self.keyboard_revision then return end
  self.keyboard_revision = revision
  if vi.active and vi.visual and not state:vi_pending() and vi.primary_generation == state.search_generation then
    return self:publish(state, enabled)
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
  self:queue_paste(state)
  return true
end
function Primary:poll(state, enabled)
  if not self.request then return nil end
  if not self.cancelled and (not self:supported(enabled) or self.target ~= state or self.scope ~= state:selection_scope()
      or not same_input(state, self.destination, self.query, self.bracketed)) then
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
        and same_input(state, next_target.destination, next_target.query, next_target.bracketed)
        and self:supported(enabled) then self:start(state) end
    return nil
  end
  if text ~= nil then text, status = Clipboard.prepare_paste(text, self.destination == "search" and {} or state.modes, self.read_limit) end
  if text and self.destination == "search" then
    local changed
    changed, status = state:search_append(text)
    self.status = status
    return nil, status, changed
  end
  self.status = status
  return text, status
end
return Primary
