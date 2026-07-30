local Binary = require("recording.binary")
local Checksum = require("recording.checksum")
local Errors = require("runtime.errors")

local Format = {}

Format.magic = "STANCZYK\0"
Format.current_major_version = 1
Format.current_minor_version = 0
Format.preamble_size = 25
Format.frame_header_size = 12
Format.frame_checksum_size = 4
Format.default_max_metadata_bytes = 65536
Format.default_max_frame_payload_bytes = 16777216
Format.kinds = {
  OUTPUT = 0x01,
  INPUT = 0x02,
  RESIZE = 0x03,
  MARK = 0x04,
  CHECKPOINT = 0x05,
  STATUS = 0x06,
  EXIT = 0x07,
  CLOCK_ADVANCE = 0x08,
}

Format.contract = {
  decode_frame_header = "decode_frame_header(bytes, offset?) -> frame_header, next_offset | nil, error",
  decode_frame = "decode_frame(bytes, offset?, limits?) -> frame, next_offset | nil, error",
  decode_metadata = "decode_metadata(bytes, offset, preamble, limits?) -> metadata_bytes, next_offset | nil, error",
  decode_preamble = "decode_preamble(bytes, offset?) -> preamble, next_offset | nil, error",
  encode_frame = "encode_frame(frame) -> bytes | nil, error",
  encode_frame_header = "encode_frame_header(frame) -> bytes | nil, error",
  encode_preamble = "encode_preamble(preamble) -> bytes | nil, error",
  frame_checksum_bytes = "frame_checksum_bytes(frame) -> bytes | nil, error",
}

local function config_error(message, detail)
  return nil, Errors.new("config_error", message, detail)
end

local function decode_offset(offset)
  if offset == nil then
    return 1
  end
  if type(offset) ~= "number" or offset % 1 ~= 0 or offset < 1 then
    return config_error("recording offset must be a positive integer", { provided = offset })
  end
  return offset
end

local function required_unsigned(value, name, maximum)
  if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > maximum then
    return config_error(name .. " must be an unsigned integer in range", { provided = value })
  end
  return value
end

local function limit(limits, name, default)
  if limits == nil then
    return default
  end
  if type(limits) ~= "table" then
    return config_error("recording limits must be a table", { provided = limits })
  end
  local value = limits[name]
  if value == nil then
    return default
  end
  return required_unsigned(value, name, 0xFFFFFFFF)
end

local function current_preamble(preamble)
  if type(preamble) ~= "table" then
    return config_error("recording preamble must be a table")
  end
  local metadata_length, length_error =
    required_unsigned(preamble.metadata_length, "metadata length", 0xFFFFFFFF)
  if not metadata_length then
    return nil, length_error
  end
  local metadata_checksum, checksum_error =
    required_unsigned(preamble.metadata_checksum, "metadata checksum", 0xFFFFFFFF)
  if not metadata_checksum then
    return nil, checksum_error
  end
  if preamble.flags ~= 0 then
    return nil, Errors.new("recording_corrupt", "bootstrap preamble flags must be zero")
  end
  return metadata_length, metadata_checksum
end

local function current_frame(header)
  if header.flags ~= 0 then
    return nil, Errors.new("recording_corrupt", "bootstrap frame flags must be zero")
  end
  if header.reserved ~= 0 then
    return nil, Errors.new("recording_corrupt", "bootstrap frame reserved field must be zero")
  end
  return true
end

local function preamble_values(preamble)
  if type(preamble) ~= "table" then
    return config_error("recording preamble must be a table")
  end
  local major_version, major_error =
    required_unsigned(preamble.major_version, "major version", 0xFFFF)
  if not major_version then
    return nil, major_error
  end
  local minor_version, minor_error =
    required_unsigned(preamble.minor_version, "minor version", 0xFFFF)
  if not minor_version then
    return nil, minor_error
  end
  local flags, flags_error = required_unsigned(preamble.flags, "preamble flags", 0xFFFFFFFF)
  if not flags then
    return nil, flags_error
  end
  local metadata_length, length_error =
    required_unsigned(preamble.metadata_length, "metadata length", 0xFFFFFFFF)
  if not metadata_length then
    return nil, length_error
  end
  local metadata_checksum, checksum_error =
    required_unsigned(preamble.metadata_checksum, "metadata checksum", 0xFFFFFFFF)
  if not metadata_checksum then
    return nil, checksum_error
  end
  return major_version, minor_version, flags, metadata_length, metadata_checksum
end

local function frame_values(frame, require_payload, require_checksum)
  if type(frame) ~= "table" then
    return config_error("recording frame must be a table")
  end
  local kind, kind_error = required_unsigned(frame.kind, "frame kind", 0xFF)
  if not kind then
    return nil, kind_error
  end
  local flags, flags_error = required_unsigned(frame.flags, "frame flags", 0xFF)
  if not flags then
    return nil, flags_error
  end
  local reserved, reserved_error = required_unsigned(frame.reserved, "frame reserved field", 0xFFFF)
  if not reserved then
    return nil, reserved_error
  end
  local delta_us, delta_error = required_unsigned(frame.delta_us, "frame delta_us", 0xFFFFFFFF)
  if not delta_us then
    return nil, delta_error
  end
  local payload_length, length_error =
    required_unsigned(frame.payload_length, "frame payload length", 0xFFFFFFFF)
  if not payload_length then
    return nil, length_error
  end
  if require_payload and type(frame.payload) ~= "string" then
    return config_error("frame payload must be bytes", { provided = frame.payload })
  end
  if require_payload and #frame.payload ~= payload_length then
    return config_error("frame payload length does not match payload", {
      declared = payload_length,
      actual = #frame.payload,
    })
  end
  if require_checksum then
    local checksum, checksum_error = required_unsigned(frame.checksum, "frame checksum", 0xFFFFFFFF)
    if not checksum then
      return nil, checksum_error
    end
    return kind, flags, reserved, delta_us, payload_length, checksum
  end
  return kind, flags, reserved, delta_us, payload_length
end

function Format.encode_preamble(preamble)
  local major_version, minor_version, flags, metadata_length, metadata_checksum =
    preamble_values(preamble)
  if not major_version then
    return nil, minor_version
  end
  return Format.magic
    .. assert(Binary.u16(major_version))
    .. assert(Binary.u16(minor_version))
    .. assert(Binary.u32(flags))
    .. assert(Binary.u32(metadata_length))
    .. assert(Binary.u32(metadata_checksum))
end

function Format.decode_preamble(bytes, offset)
  if type(bytes) ~= "string" then
    return config_error("recording input must be bytes", { provided = bytes })
  end
  local start, offset_error = decode_offset(offset)
  if not start then
    return nil, offset_error
  end
  local finish = start + Format.preamble_size - 1
  if finish > #bytes then
    return nil,
      Errors.new("recording_corrupt", "truncated recording preamble", {
        available = math.max(0, #bytes - start + 1),
        offset = start,
      })
  end
  if bytes:sub(start, start + #Format.magic - 1) ~= Format.magic then
    return nil, Errors.new("recording_corrupt", "recording magic is invalid", { offset = start })
  end
  local index = start + #Format.magic
  local major_version
  major_version, index = assert(Binary.read_u16(bytes, index))
  local minor_version
  minor_version, index = assert(Binary.read_u16(bytes, index))
  local flags
  flags, index = assert(Binary.read_u32(bytes, index))
  local metadata_length
  metadata_length, index = assert(Binary.read_u32(bytes, index))
  local metadata_checksum
  metadata_checksum, index = assert(Binary.read_u32(bytes, index))
  return {
    flags = flags,
    major_version = major_version,
    metadata_checksum = metadata_checksum,
    metadata_length = metadata_length,
    minor_version = minor_version,
  },
    index
end

function Format.encode_frame_header(frame)
  local kind, flags, reserved, delta_us, payload_length = frame_values(frame, false, false)
  if not kind then
    return nil, flags
  end
  return assert(Binary.u8(kind))
    .. assert(Binary.u8(flags))
    .. assert(Binary.u16(reserved))
    .. assert(Binary.u32(delta_us))
    .. assert(Binary.u32(payload_length))
end

function Format.decode_frame_header(bytes, offset)
  if type(bytes) ~= "string" then
    return config_error("recording input must be bytes", { provided = bytes })
  end
  local start, offset_error = decode_offset(offset)
  if not start then
    return nil, offset_error
  end
  local finish = start + Format.frame_header_size - 1
  if finish > #bytes then
    return nil,
      Errors.new("recording_corrupt", "truncated recording frame header", {
        available = math.max(0, #bytes - start + 1),
        offset = start,
      })
  end
  local kind, index = assert(Binary.read_u8(bytes, start))
  local flags
  flags, index = assert(Binary.read_u8(bytes, index))
  local reserved
  reserved, index = assert(Binary.read_u16(bytes, index))
  local delta_us
  delta_us, index = assert(Binary.read_u32(bytes, index))
  local payload_length
  payload_length, index = assert(Binary.read_u32(bytes, index))
  return {
    delta_us = delta_us,
    flags = flags,
    kind = kind,
    payload_length = payload_length,
    reserved = reserved,
  },
    index
end

function Format.decode_metadata(bytes, offset, preamble, limits)
  if type(bytes) ~= "string" then
    return config_error("recording input must be bytes", { provided = bytes })
  end
  local start, offset_error = decode_offset(offset)
  if not start then
    return nil, offset_error
  end
  local metadata_length, metadata_checksum = current_preamble(preamble)
  if not metadata_length then
    return nil, metadata_checksum
  end
  local maximum, limit_error =
    limit(limits, "max_metadata_bytes", Format.default_max_metadata_bytes)
  if not maximum then
    return nil, limit_error
  end
  if metadata_length > maximum then
    return nil,
      Errors.new("recording_corrupt", "recording metadata exceeds configured bound", {
        limit = maximum,
        provided = metadata_length,
      })
  end
  local finish = start + metadata_length - 1
  if finish > #bytes then
    return nil,
      Errors.new("recording_corrupt", "truncated recording metadata", {
        available = math.max(0, #bytes - start + 1),
        offset = start,
      })
  end
  local metadata = bytes:sub(start, finish)
  local actual_checksum, checksum_error = Checksum.crc32(metadata)
  if not actual_checksum then
    return nil, checksum_error
  end
  if actual_checksum ~= metadata_checksum then
    return nil, Errors.new("recording_corrupt", "recording metadata checksum mismatch")
  end
  return metadata, finish + 1
end

function Format.frame_checksum_bytes(frame)
  local _, flags, reserved, delta_us, payload_length = frame_values(frame, true, false)
  if not flags then
    return nil, reserved
  end
  return assert(Binary.u8(flags))
    .. assert(Binary.u16(reserved))
    .. assert(Binary.u32(delta_us))
    .. assert(Binary.u32(payload_length))
    .. frame.payload
end

function Format.decode_frame(bytes, offset, limits)
  local header, payload_offset = Format.decode_frame_header(bytes, offset)
  if not header then
    return nil, payload_offset
  end
  local current, current_error = current_frame(header)
  if not current then
    return nil, current_error
  end
  local maximum, limit_error =
    limit(limits, "max_frame_payload_bytes", Format.default_max_frame_payload_bytes)
  if not maximum then
    return nil, limit_error
  end
  if header.payload_length > maximum then
    return nil,
      Errors.new("recording_corrupt", "recording frame payload exceeds configured bound", {
        limit = maximum,
        provided = header.payload_length,
      })
  end
  local payload_end = payload_offset + header.payload_length - 1
  local checksum_offset = payload_end + 1
  local frame_end = checksum_offset + Format.frame_checksum_size - 1
  if frame_end > #bytes then
    return nil,
      Errors.new("recording_corrupt", "truncated recording frame", {
        available = math.max(0, #bytes - payload_offset + 1),
        offset = payload_offset,
      })
  end
  local payload = bytes:sub(payload_offset, payload_end)
  local checksum, next_offset = assert(Binary.read_u32(bytes, checksum_offset))
  local frame = {
    checksum = checksum,
    delta_us = header.delta_us,
    flags = header.flags,
    kind = header.kind,
    payload = payload,
    payload_length = header.payload_length,
    reserved = header.reserved,
  }
  local checksum_bytes, bytes_error = Format.frame_checksum_bytes(frame)
  if not checksum_bytes then
    return nil, bytes_error
  end
  local actual_checksum, checksum_error = Checksum.crc32(checksum_bytes)
  if not actual_checksum then
    return nil, checksum_error
  end
  if checksum ~= actual_checksum then
    return nil, Errors.new("recording_corrupt", "recording frame checksum mismatch")
  end
  return frame, next_offset
end

function Format.encode_frame(frame)
  local kind, flags, reserved, delta_us, payload_length, checksum = frame_values(frame, true, true)
  if not kind then
    return nil, flags
  end
  local header, header_error = Format.encode_frame_header({
    delta_us = delta_us,
    flags = flags,
    kind = kind,
    payload_length = payload_length,
    reserved = reserved,
  })
  if not header then
    return nil, header_error
  end
  return header .. frame.payload .. assert(Binary.u32(checksum))
end

return Format
