local assertions = require("support.assertions")
local Checksum = require("recording.checksum")
local Format = require("recording.format")

local function valid_frame(payload, kind)
  local frame = {
    delta_us = 42,
    flags = 0,
    kind = kind or Format.kinds.OUTPUT,
    payload = payload,
    payload_length = #payload,
    reserved = 0,
  }
  frame.checksum = assert(Checksum.crc32(assert(Format.frame_checksum_bytes(frame))))
  return frame
end

local function mutate(bytes, offset)
  local byte = bytes:byte(offset)
  local replacement = byte == 0 and 1 or 0
  return bytes:sub(1, offset - 1) .. string.char(replacement) .. bytes:sub(offset + 1)
end

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
  {
    name = "recording format verifies bounded metadata and frame checksums",
    run = function()
      local metadata = "{}"
      local preamble = {
        flags = 0,
        major_version = 1,
        metadata_checksum = assert(Checksum.crc32(metadata)),
        metadata_length = #metadata,
        minor_version = 0,
      }
      local prefix = assert(Format.encode_preamble(preamble))
      local decoded_preamble, metadata_offset = assert(Format.decode_preamble(prefix))
      local decoded_metadata, frame_offset =
        assert(Format.decode_metadata(prefix .. metadata, metadata_offset, decoded_preamble))
      assertions.equal(metadata, decoded_metadata)

      local frame = valid_frame("abc")
      local frame_bytes = assert(Format.encode_frame(frame))
      local decoded_frame, next_offset =
        assert(Format.decode_frame(prefix .. metadata .. frame_bytes, frame_offset))
      assertions.equal("abc", decoded_frame.payload)
      assertions.equal(42, decoded_frame.delta_us)
      assertions.equal(frame_offset + #frame_bytes, next_offset)
    end,
  },
  {
    name = "recording format rejects oversized truncated and corrupted payloads",
    run = function()
      local frame = valid_frame("abc")
      local frame_bytes = assert(Format.encode_frame(frame))
      local value, error_value =
        Format.decode_frame(frame_bytes, 1, { max_frame_payload_bytes = 2 })
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
      value, error_value = Format.decode_frame(frame_bytes:sub(1, -2))
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
      value, error_value =
        Format.decode_frame(frame_bytes:sub(1, 12) .. "abd" .. frame_bytes:sub(-4))
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)

      local metadata = "{}"
      local preamble = {
        flags = 0,
        metadata_checksum = assert(Checksum.crc32(metadata)),
        metadata_length = #metadata,
      }
      value, error_value = Format.decode_metadata(metadata, 1, preamble, { max_metadata_bytes = 1 })
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
      preamble.metadata_checksum = 0
      value, error_value = Format.decode_metadata(metadata, 1, preamble)
      assertions.falsy(value)
      assertions.equal("recording_corrupt", error_value.kind)
    end,
  },
  {
    name = "recording format negotiates matching majors and rejects unsupported majors",
    run = function()
      local version = assert(Format.negotiate_version({ major_version = 1, minor_version = 3 }))
      assertions.equal(1, version.major_version)
      assertions.equal(0, version.reader_minor_version)
      assertions.equal(3, version.recording_minor_version)
      local value, error_value = Format.negotiate_version({ major_version = 2, minor_version = 0 })
      assertions.falsy(value)
      assertions.equal("recording_unsupported_version", error_value.kind)
      assertions.equal(1, error_value.detail.supported_major_version)
      assertions.equal(2, error_value.detail.provided_major_version)
    end,
  },
  {
    name = "recording format round trips every defined frame kind without payload interpretation",
    run = function()
      local kinds = {
        Format.kinds.OUTPUT,
        Format.kinds.INPUT,
        Format.kinds.RESIZE,
        Format.kinds.MARK,
        Format.kinds.CHECKPOINT,
        Format.kinds.STATUS,
        Format.kinds.EXIT,
        Format.kinds.CLOCK_ADVANCE,
      }
      for _, kind in ipairs(kinds) do
        local payload = "\0" .. string.char(kind) .. "\255"
        local frame = valid_frame(payload, kind)
        local decoded = assert(Format.decode_frame(assert(Format.encode_frame(frame))))
        assertions.equal(kind, decoded.kind)
        assertions.equal(frame.delta_us, decoded.delta_us)
        assertions.equal(payload, decoded.payload)
        assertions.equal(frame.checksum, decoded.checksum)
      end
    end,
  },
  {
    name = "recording format rejects every truncated and protected-corrupt frame byte",
    run = function()
      local kinds = {
        Format.kinds.OUTPUT,
        Format.kinds.INPUT,
        Format.kinds.RESIZE,
        Format.kinds.MARK,
        Format.kinds.CHECKPOINT,
        Format.kinds.STATUS,
        Format.kinds.EXIT,
        Format.kinds.CLOCK_ADVANCE,
      }
      for _, kind in ipairs(kinds) do
        local bytes = assert(Format.encode_frame(valid_frame("payload", kind)))
        for length = 0, #bytes - 1 do
          local value, error_value = Format.decode_frame(bytes:sub(1, length))
          assertions.falsy(value)
          assertions.equal("recording_corrupt", error_value.kind)
        end
        for offset = 2, #bytes do
          local value, error_value = Format.decode_frame(mutate(bytes, offset))
          assertions.falsy(value)
          assertions.equal("recording_corrupt", error_value.kind)
        end
      end
    end,
  },
}
