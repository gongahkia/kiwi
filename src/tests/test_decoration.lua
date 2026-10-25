local ffi = require("ffi")
local Assert = require("tests.assert")
local Decoration = require("kiwi.text.decoration")

return {
  decoration_styles_have_distinct_bounded_masks_at_multiple_scales = function()
    for _, scale in ipairs({ 1, 2, 3 }) do
      local width, height = 12 * scale, 24 * scale
      local face = Decoration.new({ cell_width = width, cell_height = height, baseline = 18 * scale,
        underline_offset = 2 * scale, underline_thickness = scale })
      local signatures = {}
      for style = 1, 6 do
        local bitmap = face:rasterize(style)
        Assert.equal(bitmap.width, width)
        Assert.equal(bitmap.height, height)
        local signature = ffi.string(bitmap.buffer, width * height)
        Assert.equal(signatures[signature], nil)
        signatures[signature] = true
        local rows, count = {}, 0
        for row = 0, height - 1 do
          for column = 0, width - 1 do
            if bitmap.buffer[row * width + column] > 0 then rows[row] = true; count = count + 1 end
          end
        end
        Assert.truthy(count > 0 and count < width * height / 2)
        if style ~= 6 then for row in pairs(rows) do Assert.truthy(row >= 16 * scale) end end
      end
    end
  end,
  straight_underline_is_continuous_across_every_column_including_spaces = function()
    local face = Decoration.new({ cell_width = 12, cell_height = 24, baseline = 18, underline_offset = 2, underline_thickness = 1 })
    local bitmap = face:rasterize(1)
    for column = 0, 11 do Assert.equal(tonumber(bitmap.buffer[20 * 12 + column]), 255) end
    for row = 0, 23 do
      if row ~= 20 then for column = 0, 11 do Assert.equal(tonumber(bitmap.buffer[row * 12 + column]), 0) end end
    end
  end,
}
