-- One host-independent routing point for product text modes and key ownership.
local SearchInput = require("kiwi.input.search_input")
local ViInput = require("kiwi.input.vi_input")
local Search = require("kiwi.input.search")
local Vi = require("kiwi.input.vi")
local Keyboard = require("kiwi.input.keyboard")
local HintsInput = require("kiwi.input.hints_input")
local Hints = require("kiwi.input.hints")
local Input = {}
Input.__index = Input
function Input.new() return setmetatable({ search = SearchInput.new(), vi = ViInput.new(), hints = HintsInput.new() }, Input) end
function Input:claim(key) self.search:claim(key) end
function Input:key(state, key, action, modifiers, keys, clipboard, hyperlink)
  if action == keys.release then
    local owned = self.search.held[key] or self.vi.held[key] or self.hints.held[key]
    self.search.held[key], self.vi.held[key], self.hints.held[key] = nil, nil, nil
    if owned then return { handled = true, suppress_text = false } end
  end
  local hint_input = self.hints:key(state, key, action, modifiers, keys, clipboard, hyperlink)
  if hint_input then return hint_input end
  if state.vi and state.vi.active and key == keys.key_escape
      and not SearchInput.editing(state) and not state:search_pending() then
    return self.vi:key(state, key, action, modifiers, keys, clipboard, hyperlink)
  end
  local result, status = self.search:key(state, key, action, modifiers, keys, clipboard)
  if result then return result, status end
  return self.vi:key(state, key, action, modifiers, keys, clipboard, hyperlink)
end
function Input.encoding_modes(state)
  return (SearchInput.editing(state) or (state.vi and state.vi.active) or (state.hints and state.hints.active)) and {} or state.modes
end
function Input.pointer(state, event)
  if state.hints and state.hints.active then state.hints:reconcile(state); return true end
  if not state.vi or not state.vi:reconcile(state) then return false end
  if event.kind == "button" and event.button == 0 and event.action == "press" then
    state.vi:cancel(state)
    state.vi:set_position(state, state:document():top() + event.selection_row, event.selection_column)
  elseif event.kind == "wheel" and type(event.delta) == "number" and event.delta ~= 0 and event.delta == event.delta then
    state.vi:motion(state, event.delta > 0 and "scroll-up" or "scroll-down",
      math.min(16, math.max(1, math.floor(math.abs(event.delta) * 3))))
  end
  return true
end
function Input.commit(state, text, clipboard, hyperlink)
  if HintsInput.commit(state, text) then return true end
  if SearchInput.editing(state) then
    local _, status = state:search_append(text)
    return true, status
  end
  return ViInput.commit(state, text, clipboard, hyperlink)
end
function Input.text(state, codepoints, clipboard, hyperlink)
  local text = Keyboard.text_sequence(codepoints, {})
  if text == nil then return SearchInput.editing(state) or (state.vi and state.vi.active) or (state.hints and state.hints.active) or false end
  return Input.commit(state, text, clipboard, hyperlink)
end
function Input.title(state, fallback)
  if state.hints and state.hints.active then return Hints.title(state:hints_view()) end
  local search, vi = state:search_view(), state:vi_view()
  if vi.active and not search.editing and not state:search_pending() then
    local title = Vi.title(vi, fallback)
    if search.active and search.visible then
      if search.status == "matches" then return title .. "; match " .. search.current_index .. "/" .. search.match_count end
      if search.status == "stale" then return title .. "; Find: output changed; restart query" end
      return title .. (search.truncated and "; Partial Find: " or "; Find: ") .. (search.error or search.status:gsub("-", " "))
    end
    return title
  end
  return Search.title(search, Vi.title(vi, fallback))
end
return Input
