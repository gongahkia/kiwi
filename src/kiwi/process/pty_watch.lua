local ffi = require("ffi")

ffi.cdef[[
typedef struct KiwiPtyWatch KiwiPtyWatch;
KiwiPtyWatch *kiwi_surface_create_pty_watch(void);
KiwiPtyWatch *kiwi_gtk_host_create_pty_watch(void);
int kiwi_pty_watch_update(KiwiPtyWatch *watch, const int *fds, size_t count);
int kiwi_pty_watch_update_events(KiwiPtyWatch *watch, const int *fds, const uint8_t *interests, size_t count);
void kiwi_pty_watch_destroy(KiwiPtyWatch *watch);
]]

local Watch = {}
Watch.__index = Watch

function Watch.new(native, create)
  local handle = create()
  assert(handle ~= nil, "could not start terminal readiness watcher")
  return setmetatable({ native = native, handle = handle, fds = ffi.new("int[129]"), interests = ffi.new("uint8_t[129]") }, Watch)
end

function Watch:update(ptys)
  local count = 0
  for _, pty in ipairs(ptys) do
    if pty.fd ~= nil and not pty.eof then
      assert(count < 129, "too many descriptors for readiness watcher")
      self.fds[count] = pty.fd
      local pending = type(pty.pending) == "string" and (pty.pending_offset or 1) <= #pty.pending
      self.interests[count] = pending and 3 or 1
      count = count + 1
    end
    if pty.exit_fd ~= nil and not pty.exited then
      assert(count < 129, "too many descriptors for readiness watcher")
      self.fds[count], self.interests[count] = pty.exit_fd, 1
      count = count + 1
    end
  end
  assert(self.native.kiwi_pty_watch_update_events(self.handle, self.fds, self.interests, count) ~= 0, "could not update terminal readiness watcher")
end

function Watch:destroy()
  if self.handle == nil then return end
  self.native.kiwi_pty_watch_destroy(self.handle)
  self.handle = nil
end

return Watch
