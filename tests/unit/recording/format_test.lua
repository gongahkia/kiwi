local assertions = require("support.assertions")
local Format = require("recording.format")

return {
  {
    name = "recording format encodes and decodes the fixed preamble",
    run = function()
      assertions.equal(9, #Format.magic)
      assertions.equal(25, Format.preamble_size)
      local bytes = assert(Format.encode_preamble({
        flags = 0,
        major_version = 1,
        metadata_checksum = 0xCBF43926,
        metadata_length = 3,
        minor_version = 0,
      }))
      assertions.equal(
        Format.magic .. "\0\1" .. "\0\0" .. "\0\0\0\0" .. "\0\0\0\3" .. "\203\244\57\38",
        bytes
      )
      local preamble, next_offset = assert(Format.decode_preamble(bytes))
      assertions.equal(1, preamble.major_version)
      assertions.equal(0, preamble.minor_version)
      assertions.equal(0, preamble.flags)
      assertions.equal(3, preamble.metadata_length)
      assertions.equal(0xCBF43926, preamble.metadata_checksum)
      assertions.equal(26, next_offset)
    end,
  },
  {
    name = "recording format encodes frame fields in documented order",
    run = function()
      local frame = {
        checksum = 0xCBF43926,
        delta_us = 42,
        flags = 0,
        kind = Format.kinds.OUTPUT,
        payload = "abc",
        payload_length = 3,
        reserved = 0,
      }
      assertions.equal(12, Format.frame_header_size)
      assertions.equal("\1\0\0\0\0\0\0\42\0\0\0\3", assert(Format.encode_frame_header(frame)))
      assertions.equal("\0\0\0\0\0\0\42\0\0\0\3abc", assert(Format.frame_checksum_bytes(frame)))
      local bytes = assert(Format.encode_frame(frame))
      assertions.equal("\1\0\0\0\0\0\0\42\0\0\0\3abc\203\244\57\38", bytes)
      local header, next_offset = assert(Format.decode_frame_header(bytes))
      assertions.equal(Format.kinds.OUTPUT, header.kind)
      assertions.equal(0, header.flags)
      assertions.equal(0, header.reserved)
      assertions.equal(42, header.delta_us)
      assertions.equal(3, header.payload_length)
      assertions.equal(13, next_offset)
    end,
  },
  {
    name = "recording format rejects malformed structural fields",
    run = function()
      local value, error_value = Format.decode_preamble("BAD")
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
      value, error_value = Format.decode_preamble(string.rep("x", Format.preamble_size))
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
      value, error_value = Format.encode_frame_header({})
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
      value, error_value = Format.encode_frame({
        checksum = 0,
        delta_us = 0,
        flags = 0,
        kind = Format.kinds.OUTPUT,
        payload = "a",
        payload_length = 2,
        reserved = 0,
      })
      assertions.falsy(value)
      assertions.equal("config_error", error_value.kind)
    end,
  },
}
