local Assert = require("tests.assert")
local Correlation = require("kiwi.input.correlation")

return {
  input_correlation_binds_one_key_to_all_text_callbacks_in_the_event_turn = function()
    local emitted = {}
    local correlation = Correlation.new(function(codepoints, event)
      emitted[#emitted + 1] = { codepoints = codepoints, event = event }
    end)
    correlation:defer({ key = string.byte("A") })
    Assert.truthy(correlation:text(0x65))
    Assert.truthy(correlation:text(0x301))
    Assert.truthy(correlation:flush())
    Assert.equal(#emitted, 1)
    Assert.equal(emitted[1].event.key, string.byte("A"))
    Assert.equal(emitted[1].codepoints[1], 0x65)
    Assert.equal(emitted[1].codepoints[2], 0x301)
  end,
  input_correlation_flushes_an_unmatched_key_before_the_next_key = function()
    local emitted = {}
    local correlation = Correlation.new(function(codepoints, event)
      emitted[#emitted + 1] = { codepoints = codepoints, event = event }
    end)
    correlation:defer({ key = string.byte("A") })
    correlation:defer({ key = string.byte("B") })
    Assert.equal(#emitted, 1)
    Assert.equal(#emitted[1].codepoints, 0)
    Assert.equal(emitted[1].event.key, string.byte("A"))
    Assert.truthy(correlation:text(0x78))
    correlation:flush()
    Assert.equal(emitted[2].event.key, string.byte("B"))
    Assert.equal(emitted[2].codepoints[1], 0x78)
  end,
}
