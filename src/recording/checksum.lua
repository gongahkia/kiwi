local bit = require("bit")

local Errors = require("runtime.errors")

local Checksum = {}

Checksum.contract = {
  crc32 = "crc32(bytes) -> unsigned_crc32 | nil, error",
}

local reflected_polynomial = 0xEDB88320

local function unsigned(value)
  if value < 0 then
    return value + 0x100000000
  end
  return value
end

function Checksum.crc32(bytes)
  if type(bytes) ~= "string" then
    return nil, Errors.new("config_error", "checksum input must be bytes", { provided = bytes })
  end
  local crc = 0xFFFFFFFF
  for index = 1, #bytes do
    crc = bit.bxor(crc, bytes:byte(index))
    for _ = 1, 8 do
      if bit.band(crc, 1) == 1 then
        crc = bit.bxor(bit.rshift(crc, 1), reflected_polynomial)
      else
        crc = bit.rshift(crc, 1)
      end
    end
  end
  return unsigned(bit.bxor(crc, 0xFFFFFFFF))
end

return Checksum
