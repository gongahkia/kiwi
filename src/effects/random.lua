local bit = require("bit")
local Errors = require("runtime.errors")

local Random = {}
local random_mt = {}
random_mt.__index = random_mt

Random.contract = {
  derive = "derive(seed, namespace) -> u32_seed | nil, error",
  new = "new(seed) -> deterministic_random | nil, error",
  integer = "integer(minimum, maximum) -> integer | nil, error",
  next_u32 = "next_u32() -> u32",
}

local U32_MAX = 4294967295
local U32_MODULUS = 4294967296
local FALLBACK_SEED = 1831565813

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function u32(value, name)
  if
    type(value) ~= "number"
    or value ~= value
    or value % 1 ~= 0
    or value < 0
    or value > U32_MAX
  then
    return config_error(name .. " must be an unsigned 32-bit integer", { provided = value })
  end
  return value
end

local function signed(value)
  if value > 2147483647 then
    return value - U32_MODULUS
  end
  return value
end

local function unsigned(value)
  if value < 0 then
    return value + U32_MODULUS
  end
  return value
end

local function next_state(state)
  local value = signed(state)
  value = bit.bxor(value, bit.lshift(value, 13))
  value = bit.bxor(value, bit.rshift(value, 17))
  value = bit.bxor(value, bit.lshift(value, 5))
  return unsigned(value)
end

local function integer(value, name)
  if type(value) ~= "number" or value ~= value or value % 1 ~= 0 then
    return config_error(name .. " must be an integer", { provided = value })
  end
  return value
end

function Random.new(seed)
  local valid_seed, seed_error = u32(seed, "random seed")
  if valid_seed == nil then
    return nil, seed_error
  end
  if valid_seed == 0 then
    valid_seed = FALLBACK_SEED
  end
  return setmetatable({ state = valid_seed }, random_mt)
end

function Random.derive(seed, namespace)
  local valid_seed, seed_error = u32(seed, "random seed")
  if valid_seed == nil then
    return nil, seed_error
  end
  if type(namespace) ~= "string" or namespace == "" or #namespace > 128 then
    return config_error("random namespace must be a non-empty bounded string")
  end
  local state = valid_seed == 0 and FALLBACK_SEED or valid_seed
  for index = 1, #namespace do
    state = next_state(unsigned(bit.bxor(signed(state), namespace:byte(index))))
    if state == 0 then
      state = FALLBACK_SEED
    end
  end
  return state
end

function random_mt:next_u32()
  self.state = next_state(self.state)
  if self.state == 0 then
    self.state = FALLBACK_SEED
  end
  return self.state
end

function random_mt:integer(minimum, maximum)
  local lower, lower_error = integer(minimum, "random minimum")
  if lower == nil then
    return nil, lower_error
  end
  local upper, upper_error = integer(maximum, "random maximum")
  if upper == nil then
    return nil, upper_error
  end
  if lower > upper or lower < -2147483648 or upper > 2147483647 then
    return config_error("random range is outside supported bounds")
  end
  local span = upper - lower + 1
  local limit = U32_MODULUS - U32_MODULUS % span
  local value = self:next_u32()
  while value >= limit do
    value = self:next_u32()
  end
  return lower + value % span
end

return Random
