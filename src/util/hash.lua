local bit = require("bit")
local serializer = require("src.util.serializer")

local hash = { ALGORITHM = "fnv1a32", VERSION = 1 }

local BASE = 65536
local PRIME = 16777619

local function multiply(upper, lower)
  local lower_product = lower * PRIME
  local next_lower = lower_product % BASE
  local carry = math.floor(lower_product / BASE)
  local next_upper = (upper * PRIME + carry) % BASE
  return next_upper, next_lower
end

function hash.string(value)
  if type(value) ~= "string" then
    return nil, { code = "invalid_hash_input", message = "hash input must be a string" }
  end
  local upper = 33052
  local lower = 40389
  for index = 1, #value do
    lower = bit.band(bit.bxor(lower, string.byte(value, index)), 65535)
    upper, lower = multiply(upper, lower)
  end
  return string.format("%04x%04x", upper, lower)
end

function hash.of(value)
  local encoded, err = serializer.encode(value)
  if not encoded then
    return nil, err
  end
  return hash.string(encoded)
end

return hash
