local ffi = require("ffi")
ffi.cdef[[
uint64_t kiwi_process_resident_bytes(void);
double kiwi_process_monotonic_seconds(void);
const char *kiwi_process_monotonic_clock(void);
]]
local Metrics = {}
local native

local function library()
  if native ~= nil then return native end
  local root = os.getenv("KIWI_ROOT") or "."
  local path = os.getenv("KIWI_SURFACE_LIB") or root .. "/.build/native/libkiwi_surface" .. (ffi.os == "OSX" and ".dylib" or ".so")
  local ok, value = pcall(ffi.load, path)
  native = ok and value or false
  return native
end

function Metrics.resident_kib()
  local api = library()
  if not api then return nil end
  local value = tonumber(api.kiwi_process_resident_bytes())
  return value > 0 and value / 1024 or nil
end

function Metrics.monotonic_seconds()
  local api = library()
  assert(api, "native process metrics unavailable; run make native")
  local value = api.kiwi_process_monotonic_seconds()
  assert(value >= 0, "could not read monotonic clock")
  return value
end

function Metrics.clock_name()
  local api = library()
  assert(api, "native process metrics unavailable; run make native")
  return ffi.string(api.kiwi_process_monotonic_clock())
end

return Metrics
