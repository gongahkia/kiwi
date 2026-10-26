local ffi = require("ffi")
ffi.cdef[[
typedef struct KiwiPrimaryRead KiwiPrimaryRead;
KiwiPrimaryRead *kiwi_primary_read_new(const char *display_name, size_t maximum_bytes, unsigned timeout_ms);
int kiwi_primary_read_poll(KiwiPrimaryRead *read);
const char *kiwi_primary_read_text(const KiwiPrimaryRead *read, size_t *bytes);
void kiwi_primary_read_destroy(KiwiPrimaryRead *read);
]]
local Read = {}
Read.__index = Read
local live, retired = 0, {}
local statuses = { [-1] = "unavailable", [-2] = "timeout", [-3] = "over-limit", [-4] = "invalid-data" }
function Read.new(display_name, maximum_bytes)
  -- Includes conversions detached from closing windows. Bound process-wide
  -- scratch memory even if windows are repeatedly created/closed in one tick.
  if live >= 16 then return nil, "busy" end
  local native = ffi.load(os.getenv("KIWI_SURFACE_LIB") or (os.getenv("KIWI_ROOT") or ".") .. "/.build/native/libkiwi_surface.so")
  local handle = native.kiwi_primary_read_new(display_name, maximum_bytes, 1000)
  if handle == nil then return nil, "unavailable" end
  live = live + 1
  return setmetatable({ native = native, handle = ffi.gc(handle, function(value)
    native.kiwi_primary_read_destroy(value); live = live - 1
  end) }, Read)
end
function Read:poll()
  if self.handle == nil then return nil, "cancelled" end
  local status = self.native.kiwi_primary_read_poll(self.handle)
  if status == 0 then return nil, "pending" end
  local text
  if status == 1 then
    local bytes = ffi.new("size_t[1]")
    local value = self.native.kiwi_primary_read_text(self.handle, bytes)
    if value ~= nil then text = ffi.string(value, bytes[0]) end
  end
  self:destroy()
  return text, text ~= nil and "success" or statuses[status] or "platform-error"
end
function Read:destroy()
  if self.handle == nil then return end
  self.native.kiwi_primary_read_destroy(ffi.gc(self.handle, nil)); self.handle = nil
  live = live - 1
end
function Read:retire()
  if self.handle == nil or self.retired then return end
  self.retired = true
  retired[#retired + 1] = self
end
function Read.reap()
  for index = #retired, 1, -1 do
    local _, status = retired[index]:poll()
    if status ~= "pending" then table.remove(retired, index) end
  end
end
function Read.retired_count() return #retired end
function Read.wait_timeout(timeout) return #retired > 0 and math.min(timeout, 0.001) or timeout end
return Read
