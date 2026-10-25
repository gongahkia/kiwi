-- Small opaque badges, independent of terminal font-cache saturation. Each
-- letter is a 5x7 coverage mask in the glyph ID and low fifteen flag bits.
local Color = require("kiwi.renderer.color")
local Hints = { flag = 0x04000000, selected_flag = 0x08000000, prefix_flag = 0x10000000 }
local patterns = {
  a = "01110 10001 10001 11111 10001 10001 10001", b = "11110 10001 10001 11110 10001 10001 11110",
  c = "01111 10000 10000 10000 10000 10000 01111", d = "11110 10001 10001 10001 10001 10001 11110",
  e = "11111 10000 10000 11110 10000 10000 11111", f = "11111 10000 10000 11110 10000 10000 10000",
  g = "01111 10000 10000 10111 10001 10001 01111", h = "10001 10001 10001 11111 10001 10001 10001",
  i = "11111 00100 00100 00100 00100 00100 11111", j = "00111 00010 00010 00010 10010 10010 01100",
  k = "10001 10010 10100 11000 10100 10010 10001", l = "10000 10000 10000 10000 10000 10000 11111",
  m = "10001 11011 10101 10101 10001 10001 10001", n = "10001 11001 10101 10011 10001 10001 10001",
  o = "01110 10001 10001 10001 10001 10001 01110", p = "11110 10001 10001 11110 10000 10000 10000",
  q = "01110 10001 10001 10001 10101 10010 01101", r = "11110 10001 10001 11110 10100 10010 10001",
  s = "01111 10000 10000 01110 00001 00001 11110", t = "11111 00100 00100 00100 00100 00100 00100",
  u = "10001 10001 10001 10001 10001 10001 01110", v = "10001 10001 10001 10001 10001 01010 00100",
  w = "10001 10001 10001 10101 10101 10101 01010", x = "10001 10001 01010 00100 01010 10001 10001",
  y = "10001 10001 01010 00100 00100 00100 00100", z = "11111 00001 00010 00100 01000 10000 11111",
}
local masks = {}
for letter, pattern in pairs(patterns) do
  local bits, low, high = pattern:gsub(" ", ""), 0, 0
  for index = 1, #bits do
    if bits:sub(index, index) == "1" then
      if index <= 20 then low = low + 2 ^ (index - 1) else high = high + 2 ^ (index - 21) end
    end
  end
  masks[letter] = { low, high }
end
function Hints.glyphs(model)
  if not model.hints then return {}, 0 end
  local view, output = model:hints_view(), {}
  for _, label in ipairs(model.hints:labels(model)) do
    for index = 1, #label.code do
      local letter = label.code:sub(index, index)
      local at, mask = label.first + index - 1, masks[letter]
      output[#output + 1] = { x = at % model.columns, y = math.floor(at / model.columns), width = 1, height = 1,
        u0 = 0, u1 = 0, v0 = 0, v1 = 0,
        fg = Color.pack(0x20, 0x24, 0x2c, 0xff), flags = Hints.flag + mask[2] + (label.selected and Hints.selected_flag or 0)
          + (index <= #view.prefix and not label.selected and Hints.prefix_flag or 0),
        glyph_id = mask[1], cluster_column = at % model.columns }
    end
  end
  return output, view.revision
end
return Hints
