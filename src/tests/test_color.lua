local Assert = require("tests.assert")
local Color = require("kiwi.renderer.color")

return {
  terminal_colors_round_trip_through_aarrggbb_packing = function()
    local packed = Color.pack(0xd8, 0xde, 0xe9, 0xff)
    local color = Color.unpack(packed)
    Assert.equal(color.red, 0xd8)
    Assert.equal(color.green, 0xde)
    Assert.equal(color.blue, 0xe9)
    Assert.equal(color.alpha, 0xff)
  end,
}
