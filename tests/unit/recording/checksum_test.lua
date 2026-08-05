local assertions = require("support.assertions")
local Checksum = require("recording.checksum")

return {
  {
    name = "recording checksum implements CRC-32 ISO-HDLC vectors",
    run = function()
      assertions.equal(0, assert(Checksum.crc32("")))
      assertions.equal(0xCBF43926, assert(Checksum.crc32("123456789")))
      assertions.equal(0x352441C2, assert(Checksum.crc32("abc")))
    end,
  },
  {
    name = "recording checksum rejects non-byte input",
    run = function()
      local value, error_value = Checksum.crc32({})
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
    end,
  },
}
