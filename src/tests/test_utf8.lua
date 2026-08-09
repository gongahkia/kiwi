local Assert = require("tests.assert")
local Utf8 = require("kiwi.terminal.utf8")

return {
  utf8_decoder_preserves_split_multibyte_codepoints = function()
    local values = {}
    local decoder = Utf8.Decoder.new(function(codepoint, text, invalid)
      values[#values + 1] = { codepoint = codepoint, text = text, invalid = invalid }
    end)
    decoder:feed_byte(0xe2)
    decoder:feed_byte(0x82)
    Assert.equal(#values, 0)
    decoder:feed_byte(0xac)
    Assert.equal(#values, 1)
    Assert.equal(values[1].codepoint, 0x20ac)
    Assert.equal(values[1].text, "€")
    Assert.equal(values[1].invalid, false)
  end,
  utf8_decoder_replaces_truncated_sequences_deterministically = function()
    local values = {}
    local decoder = Utf8.Decoder.new(function(codepoint, _, invalid)
      values[#values + 1] = { codepoint = codepoint, invalid = invalid }
    end)
    decoder:feed_byte(0xf0)
    decoder:feed_byte(0x9f)
    decoder:finish()
    Assert.equal(#values, 1)
    Assert.equal(values[1].codepoint, 0xfffd)
    Assert.equal(values[1].invalid, true)
  end,
}
