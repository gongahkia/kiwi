local Utf8 = {}

function Utf8.encode(codepoint)
  assert(codepoint >= 0 and codepoint <= 0x10ffff, "codepoint out of range")
  if codepoint <= 0x7f then
    return string.char(codepoint)
  end
  if codepoint <= 0x7ff then
    return string.char(0xc0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
  end
  if codepoint <= 0xffff then
    return string.char(0xe0 + math.floor(codepoint / 0x1000), 0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
  end
  return string.char(0xf0 + math.floor(codepoint / 0x40000), 0x80 + math.floor(codepoint / 0x1000) % 0x40, 0x80 + math.floor(codepoint / 0x40) % 0x40, 0x80 + codepoint % 0x40)
end

function Utf8.decode_one(text)
  assert(type(text) == "string" and #text > 0, "UTF-8 text must not be empty")
  local first, second, third, fourth = text:byte(1, 4)
  if first <= 0x7f then return first end
  if first <= 0xdf then return (first - 0xc0) * 0x40 + (second - 0x80) end
  if first <= 0xef then return (first - 0xe0) * 0x1000 + (second - 0x80) * 0x40 + (third - 0x80) end
  return (first - 0xf0) * 0x40000 + (second - 0x80) * 0x1000 + (third - 0x80) * 0x40 + (fourth - 0x80)
end

local Decoder = {}
Decoder.__index = Decoder

function Decoder.new(emit)
  return setmetatable({ emit = assert(emit, "UTF-8 decoder needs an emit callback"), remaining = 0 }, Decoder)
end

function Decoder:emit_replacement()
  self.emit(0xfffd, Utf8.encode(0xfffd), true)
end

function Decoder:reset()
  self.remaining = 0
  self.codepoint = nil
  self.minimum = nil
end

function Decoder:finish()
  if self.remaining > 0 then
    self:emit_replacement()
    self:reset()
  end
end

function Decoder:feed_byte(byte)
  assert(byte >= 0 and byte <= 255, "UTF-8 byte out of range")
  if self.remaining > 0 then
    if byte >= 0x80 and byte <= 0xbf then
      self.codepoint = self.codepoint * 0x40 + (byte - 0x80)
      self.remaining = self.remaining - 1
      if self.remaining == 0 then
        local codepoint = self.codepoint
        local valid = codepoint >= self.minimum and codepoint <= 0x10ffff and (codepoint < 0xd800 or codepoint > 0xdfff)
        self:reset()
        if valid then
          self.emit(codepoint, Utf8.encode(codepoint), false)
        else
          self:emit_replacement()
        end
      end
      return
    end
    self:emit_replacement()
    self:reset()
    self:feed_byte(byte)
    return
  end

  if byte <= 0x7f then
    self.emit(byte, string.char(byte), false)
  elseif byte >= 0xc2 and byte <= 0xdf then
    self.codepoint = byte - 0xc0
    self.minimum = 0x80
    self.remaining = 1
  elseif byte >= 0xe0 and byte <= 0xef then
    self.codepoint = byte - 0xe0
    self.minimum = 0x800
    self.remaining = 2
  elseif byte >= 0xf0 and byte <= 0xf4 then
    self.codepoint = byte - 0xf0
    self.minimum = 0x10000
    self.remaining = 3
  else
    self:emit_replacement()
  end
end

Utf8.Decoder = Decoder

return Utf8
