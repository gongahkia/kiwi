local Assert = require("tests.assert")
local Grapheme = require("kiwi.unicode.grapheme")
local Utf8 = require("kiwi.terminal.utf8")
local Width = require("kiwi.terminal.width")
local fixtures = require("tests.fixtures.text.width")

local function decoded_codepoints(bytes)
  local values = {}
  local decoder = Utf8.Decoder.new(function(codepoint)
    values[#values + 1] = codepoint
  end)
  for index = 1, #bytes do decoder:feed_byte(bytes:byte(index)) end
  decoder:finish()
  return values
end

local function same_sequence(actual, expected, name)
  Assert.equal(#actual, #expected, name .. " sequence length")
  for index, value in ipairs(expected) do Assert.equal(actual[index], value, name .. " codepoint " .. index) end
end

return {
  kiwi_width_fixtures_cover_the_documented_text_categories = function()
    for _, fixture in ipairs(fixtures) do
      local codepoints = fixture.codepoints or decoded_codepoints(fixture.bytes)
      local graphemes = Grapheme.segment(codepoints)
      Assert.equal(#graphemes, #fixture.graphemes, fixture.name .. " grapheme count")
      for index, expected in ipairs(fixture.graphemes) do
        same_sequence(graphemes[index], expected, fixture.name .. " grapheme " .. index)
        Assert.equal(Width.columns(graphemes[index], fixture.policy), fixture.widths[index], fixture.name .. " width " .. index)
      end
    end
  end,
}
