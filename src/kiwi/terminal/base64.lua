local Base64 = {}

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local lookup = {}
for index = 1, #alphabet do
  lookup[alphabet:sub(index, index)] = index - 1
end

function Base64.encode(bytes)
  local chunks = {}
  for index = 1, #bytes, 3 do
    local first = bytes:byte(index)
    local second = bytes:byte(index + 1)
    local third = bytes:byte(index + 2)
    local value = first * 0x10000 + (second or 0) * 0x100 + (third or 0)
    chunks[#chunks + 1] = alphabet:sub(math.floor(value / 0x40000) % 64 + 1, math.floor(value / 0x40000) % 64 + 1)
    chunks[#chunks + 1] = alphabet:sub(math.floor(value / 0x1000) % 64 + 1, math.floor(value / 0x1000) % 64 + 1)
    chunks[#chunks + 1] = second and alphabet:sub(math.floor(value / 0x40) % 64 + 1, math.floor(value / 0x40) % 64 + 1) or "="
    chunks[#chunks + 1] = third and alphabet:sub(value % 64 + 1, value % 64 + 1) or "="
  end
  return table.concat(chunks)
end

function Base64.decode(encoded)
  assert(#encoded % 4 == 0, "invalid base64 length")
  local chunks = {}
  for index = 1, #encoded, 4 do
    local first = lookup[encoded:sub(index, index)]
    local second = lookup[encoded:sub(index + 1, index + 1)]
    local third_character = encoded:sub(index + 2, index + 2)
    local fourth_character = encoded:sub(index + 3, index + 3)
    local third = third_character == "=" and nil or lookup[third_character]
    local fourth = fourth_character == "=" and nil or lookup[fourth_character]
    assert(first and second and (third or third_character == "=") and (fourth or fourth_character == "="), "invalid base64 data")
    assert(not (third_character == "=" and fourth_character ~= "="), "invalid base64 padding")
    local value = first * 0x40000 + second * 0x1000 + (third or 0) * 0x40 + (fourth or 0)
    chunks[#chunks + 1] = string.char(math.floor(value / 0x10000) % 0x100)
    if third then
      chunks[#chunks + 1] = string.char(math.floor(value / 0x100) % 0x100)
    end
    if fourth then
      chunks[#chunks + 1] = string.char(value % 0x100)
    end
  end
  return table.concat(chunks)
end

return Base64
