local bit = require("bit")

local Color = {}

function Color.pack(red, green, blue, alpha)
  assert(red >= 0 and red <= 255, "red must fit in one byte")
  assert(green >= 0 and green <= 255, "green must fit in one byte")
  assert(blue >= 0 and blue <= 255, "blue must fit in one byte")
  assert(alpha >= 0 and alpha <= 255, "alpha must fit in one byte")
  return bit.tobit(bit.bor(bit.lshift(alpha, 24), bit.lshift(red, 16), bit.lshift(green, 8), blue))
end

function Color.unpack(value)
  value = bit.tobit(value)
  return {
    red = bit.band(bit.rshift(value, 16), 0xff),
    green = bit.band(bit.rshift(value, 8), 0xff),
    blue = bit.band(value, 0xff),
    alpha = bit.band(bit.rshift(value, 24), 0xff),
  }
end

return Color
