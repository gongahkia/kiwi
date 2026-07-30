package.path = "./?.lua;./?/init.lua;" .. package.path

local id_allocator = require("src.util.id_allocator")
local hash = require("src.util.hash")
local prng = require("src.util.prng")
local serializer = require("src.util.serializer")

local function fail(error_value)
  io.stderr:write(error_value.code .. ": " .. error_value.message .. "\n")
  os.exit(1)
end

local ids, id_error = id_allocator.new(1)
if not ids then
  fail(id_error)
end
local random, prng_error = prng.new(1)
if not random then
  fail(prng_error)
end

local payload = {
  format_version = 1,
  ids = { ids:next(), ids:next() },
  random_values = { random:next_u32(), random:next_u32() },
}
local encoded, serializer_error = serializer.encode(payload)
if not encoded then
  fail(serializer_error)
end
local digest, hash_error = hash.string(encoded)
if not digest then
  fail(hash_error)
end
io.write("HEADLESS_OK " .. digest .. "\n")
