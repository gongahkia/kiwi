local Utils = {}

function Utils.clamp(value, low, high)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

function Utils.mix(a, b, t)
  return a + (b - a) * t
end

function Utils.keyOf(x, y)
  return x .. ":" .. y
end

function Utils.sign(value)
  if value < 0 then
    return -1
  elseif value > 0 then
    return 1
  end
  return 0
end

Utils.neighbors = {
  { 1, 0 },
  { -1, 0 },
  { 0, 1 },
  { 0, -1 },
}

return Utils
