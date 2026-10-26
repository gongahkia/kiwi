local ffi = require("ffi")
ffi.cdef[[
typedef struct KiwiGtkPrimaryRead KiwiGtkPrimaryRead;
KiwiGtkPrimaryRead *kiwi_gtk_host_primary_read_new(KiwiGtkHost *host, size_t maximum_bytes);
int kiwi_gtk_primary_read_poll(KiwiGtkPrimaryRead *read);
const char *kiwi_gtk_primary_read_text(const KiwiGtkPrimaryRead *read, size_t *bytes);
void kiwi_gtk_primary_read_destroy(KiwiGtkPrimaryRead *read);
]]
local Read = {}
Read.__index = Read
local statuses = { [-1] = "unavailable", [-2] = "timeout", [-3] = "over-limit", [-4] = "invalid-data" }
function Read.new(native, host, maximum_bytes)
  assert(type(maximum_bytes) == "number" and maximum_bytes >= 1 and maximum_bytes <= 1024 * 1024
    and maximum_bytes % 1 == 0, "PRIMARY read limit must be an integer from 1 to 1048576")
  local handle = native.kiwi_gtk_host_primary_read_new(host, maximum_bytes)
  if handle == nil then return nil, "busy" end
  return setmetatable({ native = native, handle = ffi.gc(handle, native.kiwi_gtk_primary_read_destroy) }, Read)
end
function Read:poll()
  if self.handle == nil then return nil, "cancelled" end
  local status = self.native.kiwi_gtk_primary_read_poll(self.handle)
  if status == 0 then return nil, "pending" end
  local text
  if status == 1 then
    local bytes = ffi.new("size_t[1]")
    local value = self.native.kiwi_gtk_primary_read_text(self.handle, bytes)
    if value ~= nil then text = ffi.string(value, bytes[0]) end
  end
  self:destroy()
  return text, text ~= nil and "success" or statuses[status] or "platform-error"
end
function Read:destroy()
  if self.handle == nil then return end
  self.native.kiwi_gtk_primary_read_destroy(ffi.gc(self.handle, nil))
  self.handle = nil
end
-- GDK cancellation owns any outstanding callbacks; no X11 conversion window
-- needs to be retained or polled after its terminal closes.
Read.retire = Read.destroy
return Read
