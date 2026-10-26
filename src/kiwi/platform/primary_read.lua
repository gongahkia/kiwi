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
local statuses = { [-1] = "unavailable", [-2] = "timeout", [-3] = "over-limit", [-4] = "invalid-data" }
function Read.new(display_name, maximum_bytes)
  local native = ffi.load(os.getenv("KIWI_SURFACE_LIB") or (os.getenv("KIWI_ROOT") or ".") .. "/.build/native/libkiwi_surface.so")
  local handle = native.kiwi_primary_read_new(display_name, maximum_bytes, 1000)
  if handle == nil then return nil, "unavailable" end
  return setmetatable({ native = native, handle = ffi.gc(handle, native.kiwi_primary_read_destroy) }, Read)
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
end
return Read
