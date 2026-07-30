local assertions = require("support.assertions")
local Utf8 = require("terminal.utf8")

local REPLACEMENT = "\239\191\189"

return {
  {
    name = "UTF-8 decoder emits ASCII and split multibyte text",
    run = function()
      local decoder = Utf8.new()
      assertions.equal("A", assert(decoder:push(string.byte("A")))[1])
      assertions.equal(0, #assert(decoder:push(0xC3)))
      local output = assert(decoder:push(0xA9))
      assertions.equal("é", output[1])
      assertions.equal(0, decoder:snapshot().remaining)
    end,
  },
  {
    name = "UTF-8 decoder replaces malformed and incomplete sequences",
    run = function()
      local decoder = Utf8.new()
      assert(decoder:push(0xC3))
      local output = assert(decoder:push(string.byte("x")))
      assertions.equal(REPLACEMENT, output[1])
      assertions.equal("x", output[2])

      decoder = Utf8.new()
      assert(decoder:push(0xE0))
      assert(decoder:push(0x80))
      output = assert(decoder:push(0x80))
      assertions.equal(REPLACEMENT, output[1])

      decoder = Utf8.new()
      assert(decoder:push(0xF0))
      assertions.equal(REPLACEMENT, decoder:finish()[1])
    end,
  },
  {
    name = "UTF-8 decoder rejects non-byte input",
    run = function()
      local output, error_value = Utf8.new():push(256)
      assertions.falsy(output)
      assertions.equal("config_error", error_value.kind)
    end,
  },
}
