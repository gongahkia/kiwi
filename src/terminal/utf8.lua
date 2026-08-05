local Errors = require("runtime.errors")

local Utf8 = {}
local utf8_mt = {}
utf8_mt.__index = utf8_mt

Utf8.contract = {
  finish = "finish() -> decoded_text",
  new = "new() -> decoder",
  push = "push(byte) -> decoded_text | nil, error",
  snapshot = "snapshot() -> decoder_state",
}

local REPLACEMENT = "\239\191\189"

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function valid_byte(byte)
  return type(byte) == "number" and byte % 1 == 0 and byte >= 0 and byte <= 255
end

local function reset(decoder)
  decoder.codepoint = 0
  decoder.minimum = 0
  decoder.remaining = 0
end

local function encode(codepoint)
  if codepoint <= 0x7F then
    return string.char(codepoint)
  end
  if codepoint <= 0x7FF then
    return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + (codepoint % 0x40))
  end
  if codepoint <= 0xFFFF then
    return string.char(
      0xE0 + math.floor(codepoint / 0x1000),
      0x80 + (math.floor(codepoint / 0x40) % 0x40),
      0x80 + (codepoint % 0x40)
    )
  end
  return string.char(
    0xF0 + math.floor(codepoint / 0x40000),
    0x80 + (math.floor(codepoint / 0x1000) % 0x40),
    0x80 + (math.floor(codepoint / 0x40) % 0x40),
    0x80 + (codepoint % 0x40)
  )
end

local function complete(decoder, output)
  local codepoint = decoder.codepoint
  local valid = codepoint >= decoder.minimum
    and codepoint <= 0x10FFFF
    and not (codepoint >= 0xD800 and codepoint <= 0xDFFF)
  reset(decoder)
  output[#output + 1] = valid and encode(codepoint) or REPLACEMENT
end

local function start_sequence(decoder, output, byte)
  if byte <= 0x7F then
    output[#output + 1] = string.char(byte)
  elseif byte >= 0xC2 and byte <= 0xDF then
    decoder.codepoint = byte - 0xC0
    decoder.minimum = 0x80
    decoder.remaining = 1
  elseif byte >= 0xE0 and byte <= 0xEF then
    decoder.codepoint = byte - 0xE0
    decoder.minimum = 0x800
    decoder.remaining = 2
  elseif byte >= 0xF0 and byte <= 0xF4 then
    decoder.codepoint = byte - 0xF0
    decoder.minimum = 0x10000
    decoder.remaining = 3
  else
    output[#output + 1] = REPLACEMENT
  end
end

function Utf8.new()
  return setmetatable({ codepoint = 0, minimum = 0, remaining = 0 }, utf8_mt)
end

function utf8_mt:push(byte)
  if not valid_byte(byte) then
    return config_error("UTF-8 input must be a byte", { provided = byte })
  end
  local output = {}
  local current = byte
  while current ~= nil do
    if self.remaining == 0 then
      start_sequence(self, output, current)
      current = nil
    elseif current >= 0x80 and current <= 0xBF then
      self.codepoint = self.codepoint * 0x40 + (current - 0x80)
      self.remaining = self.remaining - 1
      if self.remaining == 0 then
        complete(self, output)
      end
      current = nil
    else
      output[#output + 1] = REPLACEMENT
      reset(self)
    end
  end
  return output
end

function utf8_mt:finish()
  if self.remaining == 0 then
    return {}
  end
  reset(self)
  return { REPLACEMENT }
end

function utf8_mt:snapshot()
  return {
    codepoint = self.codepoint,
    minimum = self.minimum,
    remaining = self.remaining,
  }
end

return Utf8
