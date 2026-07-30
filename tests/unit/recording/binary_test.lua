local assertions = require("support.assertions")
local Binary = require("recording.binary")

return {
  {
    name = "recording binary encodes unsigned big-endian integers",
    run = function()
      assertions.equal("\18", assert(Binary.u8(0x12)))
      assertions.equal("\18\52", assert(Binary.u16(0x1234)))
      assertions.equal("\18\52\86\120", assert(Binary.u32(0x12345678)))
      assertions.equal("\255\255\255\255", assert(Binary.u32(0xFFFFFFFF)))
    end,
  },
  {
    name = "recording binary decodes unsigned big-endian integers",
    run = function()
      local bytes = "\18\52\86\120\154\188\222"
      local value, next_offset = assert(Binary.read_u8(bytes))
      assertions.equal(0x12, value)
      assertions.equal(2, next_offset)
      value, next_offset = assert(Binary.read_u16(bytes, next_offset))
      assertions.equal(0x3456, value)
      assertions.equal(4, next_offset)
      value, next_offset = assert(Binary.read_u32(bytes, next_offset))
      assertions.equal(0x789ABCDE, value)
      assertions.equal(8, next_offset)
    end,
  },
  {
    name = "recording binary rejects invalid and truncated values",
    run = function()
      local bytes, error_value = Binary.u16(-1)
      assertions.falsy(bytes)
      assertions.equal("config_error", error_value.kind)
      bytes, error_value = Binary.u32(0x100000000)
      assertions.falsy(bytes)
      assertions.equal("config_error", error_value.kind)
      local value
      value, error_value = Binary.read_u32("\0\0\0")
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
      value, error_value = Binary.read_u8("\0", 0)
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
    end,
  },
}
