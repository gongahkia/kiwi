-- Commands are taken from committed text, so keyboard layouts and Unicode
-- inline-find targets work without translating physical US key positions.
local bit = require("bit")
local Utf8 = require("kiwi.terminal.utf8")
local Vi = require("kiwi.input.vi")
local Input = {}
Input.__index = Input
function Input.new() return setmetatable({ held = {} }, Input) end
local motions = { h = "left", j = "down", k = "up", l = "right", w = "word-next",
  b = "word-back", e = "word-end", W = "word-next", B = "word-back", E = "word-end",
  ["0"] = "first", ["^"] = "first-occupied", ["$"] = "last", G = "bottom",
  H = "high", M = "middle", L = "low", ["%"] = "bracket" }
local function count(vi)
  local value = tonumber(vi.count)
  vi.count = ""
  return value
end
local function copy(state, clipboard)
  if state:vi_pending() then state.vi.status = "moving"; return end
  local ok, status
  if clipboard then ok, status = clipboard:copy(state) end
  if ok then state.vi:cancel(state); state.vi.status = "copied"
  else state.vi.status = status or "clipboard-unavailable" end
end

function Input.command(state, text, clipboard, hyperlink)
  local vi = state.vi
  if not vi:reconcile(state) then return end
  if vi.awaiting then
    local spec = vi.awaiting; vi.awaiting = nil
    vi:inline(state, text, spec.direction, spec.till, spec.count)
    return
  end
  if text:match("^[0-9]$") and (text ~= "0" or #vi.count > 0) then
    local value = tonumber(vi.count .. text)
    vi.count = tostring(math.min(Vi.maximum_count, value)); return
  end
  local amount, prefix = count(vi), vi.prefix
  vi.prefix = nil
  if prefix then
    if prefix == "g" and text == "g" then vi:motion(state, "top", amount)
    elseif prefix == "z" and text == "z" then vi:motion(state, "center") end
    return
  end
  if text == "g" or text == "z" then vi.prefix, vi.count = text, amount and tostring(amount) or ""
  elseif motions[text] then
    vi:motion(state, motions[text], amount, (text == "W" or text == "B" or text == "E") and "big" or nil)
  elseif text == "v" or text == "V" then vi:toggle_selection(state, text == "v" and "character" or "line")
  elseif text == "i" then vi:leave(state, true)
  elseif text == "y" then copy(state, clipboard)
  elseif text == "f" or text == "F" or text == "t" or text == "T" then
    vi.awaiting = { direction = (text == "f" or text == "t") and 1 or -1,
      till = text == "t" or text == "T", count = amount }
  elseif (text == ";" or text == ",") and vi.last_inline then
    local spec = vi.last_inline
    vi:inline(state, spec.text, spec.direction * (text == ";" and 1 or -1), spec.till, amount, true)
  elseif text == "/" or text == "?" then
    vi.job = nil
    state:search_begin(text == "/" and "forward" or "backward", "regex")
  elseif text == "n" or text == "N" then
    local direction = vi.search_direction or "forward"
    if text == "N" then direction = direction == "forward" and "backward" or "forward" end
    -- Search has at most 256 results; reduce a count before navigating.
    local matches = state:search_view().match_count
    if matches > 0 then
      local steps = ((amount or 1) - 1) % matches + 1
      for _ = 1, steps do state:search_navigate(direction) end
    end
  elseif text == "\r" and hyperlink then
    local view = vi:view(state)
    local opened, status = hyperlink:activate(state:hyperlink_at(view.row, view.column))
    vi.status = opened and "opened-link" or status
  end
end

function Input.commit(state, text, clipboard, hyperlink)
  if not state.vi or not state.vi:reconcile(state) then return false end
  local index, operations = 1, 0
  -- Multi-scalar commits are consumed atomically, even if one command exits
  -- vi. Never route the rest of that commit to the child application.
  while index <= #text and state.vi.active and operations < 256 do
    local byte = text:byte(index)
    local length = byte < 0x80 and 1 or byte < 0xe0 and 2 or byte < 0xf0 and 3 or 4
    local scalar = text:sub(index, index + length - 1)
    Input.command(state, Utf8.encode(Utf8.decode_one(scalar)), clipboard, hyperlink)
    index, operations = index + length, operations + 1
    if state.search.editing then
      -- The remainder of a committed IME string is query text, not commands.
      if index <= #text then state:search_append(text:sub(index)) end
      break
    end
  end
  if index <= #text and operations == 256 and state.vi.active then state.vi.status = "input-limit" end
  return true
end

function Input:key(state, key, action, modifiers, keys, clipboard, hyperlink)
  if action == keys.release and self.held[key] then
    self.held[key] = nil
    return { handled = true, suppress_text = false }
  end
  if action == keys.press then self.held[key] = nil end
  local active = state.vi and state.vi:reconcile(state)
  if action == keys.repeat_action and self.held[key] and not active then
    return { handled = true, suppress_text = true }
  end
  if not active then return nil end
  if action == keys.release then return { handled = true, suppress_text = false } end
  self.held[key] = true
  local control, shift = bit.band(modifiers, keys.mod_control) ~= 0, bit.band(modifiers, keys.mod_shift) ~= 0
  local alt, super = bit.band(modifiers, keys.mod_alt) ~= 0, bit.band(modifiers, keys.mod_super) ~= 0
  local vi, suppress = state.vi, true
  if key == keys.key_escape then vi:cancel(state); state:clear_search()
  elseif control and not alt and not super then
    if (key == string.byte("C") or (key == keys.key_space and shift)) and action == keys.press then vi:leave(state, true)
    elseif key == string.byte("V") and not shift then
      if action == keys.press then vi:toggle_selection(state, "block") end
    else
      local motion = ({ [string.byte("B")] = "page-up", [string.byte("F")] = "page-down",
        [string.byte("U")] = "half-up", [string.byte("D")] = "half-down",
        [string.byte("Y")] = "scroll-up", [string.byte("E")] = "scroll-down" })[key]
      if motion and not shift then vi:motion(state, motion, count(vi)) end
    end
  elseif alt and not control and not super and key == string.byte("V") then
    if action == keys.press then vi:toggle_selection(state, "word") end
  elseif key == keys.key_enter then
    if action == keys.press then Input.command(state, "\r", clipboard, hyperlink) end
  else
    local motion = ({ [keys.key_left] = "left", [keys.key_right] = "right", [keys.key_up] = "up",
      [keys.key_down] = "down", [keys.key_home] = "first", [keys.key_end] = "last",
      [keys.key_page_up] = "page-up", [keys.key_page_down] = "page-down" })[key]
    if motion then vi:motion(state, motion, count(vi)) else suppress = super or (control and not alt) end
  end
  return { handled = true, suppress_text = suppress }
end
return Input
