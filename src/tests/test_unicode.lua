local Assert = require("tests.assert")
local Grapheme = require("kiwi.unicode.grapheme")
local Properties = require("kiwi.unicode.properties")

local function grapheme_cases()
  local cases = {}
  for line in io.lines("unicode/17.0.0/auxiliary/GraphemeBreakTest.txt") do
    local body = line:match("^%s*(.-)%s*#") or line
    if body:find("÷", 1, true) then
      local codepoints, expected = {}, {}
      local boundary
      for token in body:gmatch("%S+") do
        if token == "÷" then
          boundary = true
        elseif token == "×" then
          boundary = false
        else
          codepoints[#codepoints + 1] = assert(tonumber(token, 16), "invalid GraphemeBreakTest codepoint")
          expected[#codepoints] = boundary
          boundary = nil
        end
      end
      expected[#codepoints + 1] = true
      cases[#cases + 1] = { codepoints = codepoints, expected = expected }
    end
  end
  return cases
end

return {
  unicode_data_is_pinned_to_17_0 = function()
    Assert.equal(Properties.version, "17.0.0")
    Assert.equal(Properties.gcb(0x0301), Properties.grapheme_break.extend)
    Assert.truthy(Properties.has("extended_pictographic", 0x1f469))
    Assert.equal(Properties.east_asian_width_of(0x4e2d), Properties.east_asian_width.wide)
  end,
  unicode_extended_grapheme_conforms_to_the_pinned_official_corpus = function()
    local cases = grapheme_cases()
    Assert.equal(#cases, 766)
    for case_index, case in ipairs(cases) do
      local actual = Grapheme.boundaries(case.codepoints)
      for index = 1, #case.expected do
        Assert.equal(actual[index], case.expected[index], "GraphemeBreakTest case " .. case_index .. " boundary " .. index)
      end
    end
  end,
}
