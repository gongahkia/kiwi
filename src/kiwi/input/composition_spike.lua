local Utf8 = require("kiwi.terminal.utf8")

local Composition = {}
Composition.__index = Composition

Composition.maximum_bytes = 1024

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

local function byte_boundary(text, index)
  if index < 0 or index > #text then return false end
  if index == #text then return true end
  local byte = text:byte(index + 1)
  return byte < 0x80 or byte > 0xbf
end

local function empty_preedit()
  return { cursor_begin = 0, cursor_end = 0, text = "" }
end

local function copy_preedit(preedit)
  return {
    cursor_begin = preedit.cursor_begin,
    cursor_end = preedit.cursor_end,
    text = preedit.text,
  }
end

function Composition.new(options)
  options = options or {}
  local maximum_bytes = options.maximum_bytes or Composition.maximum_bytes
  assert(type(maximum_bytes) == "number" and maximum_bytes >= 1 and maximum_bytes % 1 == 0, "composition byte limit must be a positive integer")
  return setmetatable({
    focused = false,
    maximum_bytes = maximum_bytes,
    pending_commit = "",
    pending_preedit = empty_preedit(),
    preedit = empty_preedit(),
  }, Composition)
end

function Composition:enter()
  self.focused = true
  self.pending_commit = ""
  self.pending_preedit = empty_preedit()
  self.preedit = empty_preedit()
end

function Composition:leave()
  self.focused = false
  self.pending_commit = ""
  self.pending_preedit = empty_preedit()
  self.preedit = empty_preedit()
end

function Composition:offer_preedit(text, cursor_begin, cursor_end)
  if not self.focused then return false, "inactive" end
  if type(text) ~= "string" or #text > self.maximum_bytes or not valid_utf8(text) then return false, "invalid-preedit" end
  if cursor_begin == -1 and cursor_end == -1 then
    self.pending_preedit = { cursor_begin = cursor_begin, cursor_end = cursor_end, text = text }
    return true, "pending"
  end
  if type(cursor_begin) ~= "number" or type(cursor_end) ~= "number" or cursor_begin % 1 ~= 0 or cursor_end % 1 ~= 0
    or not byte_boundary(text, cursor_begin) or not byte_boundary(text, cursor_end) then
    return false, "invalid-preedit"
  end
  self.pending_preedit = { cursor_begin = cursor_begin, cursor_end = cursor_end, text = text }
  return true, "pending"
end

function Composition:offer_commit(text)
  if not self.focused then return false, "inactive" end
  if type(text) ~= "string" or #text > self.maximum_bytes - #self.pending_commit or not valid_utf8(text) then
    return false, "invalid-commit"
  end
  self.pending_commit = self.pending_commit .. text
  return true, "pending"
end

function Composition:done()
  if not self.focused then return nil, "inactive" end
  self.preedit = copy_preedit(self.pending_preedit)
  local update = { commit = self.pending_commit, preedit = copy_preedit(self.preedit) }
  self.pending_commit = ""
  self.pending_preedit = empty_preedit()
  return update, "applied"
end

function Composition:snapshot()
  return {
    focused = self.focused,
    maximum_bytes = self.maximum_bytes,
    preedit_bytes = #self.preedit.text,
  }
end

return Composition
