local ffi = require("ffi")

ffi.cdef[[
typedef struct KiwiPtyWatch KiwiPtyWatch;
KiwiPtyWatch *kiwi_surface_create_pty_watch(void);
KiwiPtyWatch *kiwi_gtk_host_create_pty_watch(void);
int kiwi_pty_watch_update(KiwiPtyWatch *watch, const int *fds, size_t count);
void kiwi_pty_watch_destroy(KiwiPtyWatch *watch);
]]

local Watch = {}
Watch.__index = Watch

function Watch.new(native, create)
  local handle = create()
  assert(handle ~= nil, "could not start terminal readiness watcher")
  return setmetatable({ native = native, handle = handle, fds = ffi.new("int[65]") }, Watch)
end

function Watch:update(ptys)
  local count = 0
  for _, pty in ipairs(ptys) do
    if pty.fd ~= nil and not pty.eof then
      assert(count < 65, "too many descriptors for readiness watcher")
      self.fds[count] = pty.fd
      count = count + 1
    end
  end
  assert(self.native.kiwi_pty_watch_update(self.handle, self.fds, count) ~= 0, "could not update terminal readiness watcher")
end

function Watch:destroy()
  if self.handle == nil then return end
  self.native.kiwi_pty_watch_destroy(self.handle)
  self.handle = nil
end

return Watch
