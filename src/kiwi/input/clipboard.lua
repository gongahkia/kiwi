local Utf8 = require("kiwi.terminal.utf8")

local Clipboard = {}
Clipboard.__index = Clipboard

Clipboard.maximum_bytes = 1024 * 1024

local opening = "\27[200~"
local closing = "\27[201~"

local function valid_utf8(text)
  if text:find("\0", 1, true) then return false end
  local valid = true
  local decoder = Utf8.Decoder.new(function(_, _, replaced)
    if replaced then valid = false end
  end)
  for index = 1, #text do decoder:feed_byte(text:byte(index)) end
  decoder:finish()
  return valid
end

local function copy_counters(counters)
  local copy = {}
  for key, value in pairs(counters) do copy[key] = value end
  return copy
end

function Clipboard.new(bridge, options)
  options = options or {}
  assert(type(bridge) == "table" and type(bridge.clipboard_read) == "function" and type(bridge.clipboard_write) == "function", "clipboard needs a read/write platform bridge")
  local maximum_bytes = options.maximum_bytes or Clipboard.maximum_bytes
  assert(type(maximum_bytes) == "number" and maximum_bytes >= 1 and maximum_bytes % 1 == 0, "clipboard byte limit must be a positive integer")
  return setmetatable({
    bridge = bridge,
    maximum_bytes = maximum_bytes,
    counters = {
      copy_success = 0,
      copy_no_selection = 0,
      copy_over_limit = 0,
      copy_unavailable = 0,
      copy_platform_error = 0,
      paste_success = 0,
      paste_empty = 0,
      paste_over_limit = 0,
      paste_invalid_utf8 = 0,
      paste_unavailable = 0,
      paste_platform_error = 0,
    },
  }, Clipboard)
end

function Clipboard:record(kind, status)
  status = status:gsub("-", "_")
  local key = kind .. "_" .. status
  if self.counters[key] == nil then key = kind .. "_platform_error" end
  self.counters[key] = self.counters[key] + 1
end

function Clipboard:copy(state)
  local text, status = state:selection_text(self.maximum_bytes)
  if text == nil then
    self:record("copy", status)
    return false, status
  end
  local written, write_status = self.bridge:clipboard_write(text)
  if not written then
    status = write_status == "unavailable" and "unavailable" or "platform_error"
    self:record("copy", status)
    return false, status
  end
  self:record("copy", "success")
  return true, "success"
end

function Clipboard:paste(state)
  local text, status = self.bridge:clipboard_read(self.maximum_bytes)
  if text == nil then
    status = status == "over-limit" and "over_limit" or status == "unavailable" and "unavailable" or "platform_error"
    self:record("paste", status)
    return nil, status
  end
  if #text > self.maximum_bytes then
    self:record("paste", "over_limit")
    return nil, "over_limit"
  end
  if not valid_utf8(text) then
    self:record("paste", "invalid_utf8")
    return nil, "invalid_utf8"
  end
  if #text == 0 then
    self:record("paste", "empty")
    return nil, "empty"
  end
  if state.modes.bracketed_paste then text = opening .. text .. closing end
  self:record("paste", "success")
  return text, "success"
end

function Clipboard:snapshot()
  return { maximum_bytes = self.maximum_bytes, counters = copy_counters(self.counters) }
end

return Clipboard
