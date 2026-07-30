local bit = require("bit")

local prng = { MAX_UINT32 = 4294967295 }
local generator = {}
generator.__index = generator

local MODULUS = 4294967296
local HALF_MODULUS = 2147483648

local function to_u32(value)
  if value < 0 then
    return value + MODULUS
  end
  return value
end

local function is_u32(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
    and value == math.floor(value)
    and value >= 0
    and value <= prng.MAX_UINT32
end

local function next_state(state)
  local signed = state
  if signed >= HALF_MODULUS then
    signed = signed - MODULUS
  end
  signed = bit.bxor(signed, bit.lshift(signed, 13))
  signed = bit.bxor(signed, bit.rshift(signed, 17))
  signed = bit.bxor(signed, bit.lshift(signed, 5))
  return to_u32(signed)
end

local function derive_seed(seed, label)
  local state = seed
  for index = 1, #label do
    state = to_u32(bit.bxor(state, string.byte(label, index)))
    state = next_state(state)
  end
  return state == 0 and 1831565813 or state
end

function prng.new(seed)
  if not is_u32(seed) or seed == 0 then
    return nil, { code = "invalid_seed", message = "seed must be a non-zero uint32" }
  end
  return setmetatable({ state_value = seed }, generator)
end

function generator:state()
  return self.state_value
end

function generator:next_u32()
  self.state_value = next_state(self.state_value)
  return self.state_value
end

function generator:next_float()
  return self:next_u32() / MODULUS
end

function generator:next_int(minimum, maximum)
  if
    type(minimum) ~= "number"
    or type(maximum) ~= "number"
    or minimum ~= math.floor(minimum)
    or maximum ~= math.floor(maximum)
    or minimum > maximum
  then
    return nil, { code = "invalid_range", message = "range must contain ordered integers" }
  end

  local span = maximum - minimum + 1
  if span > MODULUS then
    return nil, { code = "invalid_range", message = "range exceeds uint32 output" }
  end
  if span == MODULUS then
    return minimum + self:next_u32()
  end

  local limit = MODULUS - (MODULUS % span)
  local value = self:next_u32()
  while value >= limit do
    value = self:next_u32()
  end
  return minimum + (value % span)
end

function generator:fork(label)
  if type(label) ~= "string" or label == "" then
    return nil,
      { code = "invalid_stream_label", message = "stream label must be a non-empty string" }
  end
  return prng.new(derive_seed(self.state_value, label))
end

return prng
