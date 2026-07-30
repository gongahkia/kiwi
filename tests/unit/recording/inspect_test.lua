local assertions = require("support.assertions")
local Format = require("recording.format")
local Inspect = require("recording.inspect")

return {
  {
    name = "recording inspection escapes bounded raw bytes",
    run = function()
      assertions.equal('"A\\x00\\\\\\""', assert(Inspect.escape_bytes('A\0\\"')))
      assertions.equal('"ab"...', assert(Inspect.escape_bytes("abcd", 2)))
      local value, error_value = Inspect.escape_bytes("bytes", -1)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
    end,
  },
  {
    name = "recording inspection describes frames without decoding arbitrary payloads",
    run = function()
      local line, elapsed = assert(Inspect.frame_line(1, "4294967295", {
        delta_us = 1,
        kind = Format.kinds.OUTPUT,
        payload = "ok",
      }))
      assertions.equal("4294967296", elapsed)
      assertions.equal('1 elapsed_us=4294967296 delta_us=1 output bytes=2 data="ok"', line)
      line, elapsed = assert(Inspect.frame_line(2, elapsed, {
        delta_us = 3,
        kind = Format.kinds.RESIZE,
        payload = "\0\0\0P\0\0\0\24\0\0\3 \0\0\2X",
      }))
      assertions.equal("4294967299", elapsed)
      assertions.equal(
        "2 elapsed_us=4294967299 delta_us=3 resize columns=80 rows=24 pixel_width=800 pixel_height=600",
        line
      )
      line = assert(Inspect.frame_line(3, elapsed, {
        delta_us = 0,
        kind = 0x80,
        payload = "extension",
      }))
      assertions.equal("3 elapsed_us=4294967299 delta_us=0 unknown_0x80 bytes=9", line)
    end,
  },
}
