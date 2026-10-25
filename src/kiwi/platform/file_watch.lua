local ffi = require("ffi")
ffi.cdef[[
typedef struct KiwiFileWatch KiwiFileWatch;
KiwiFileWatch *kiwi_file_watch_create(const char *const *paths, size_t count);
int kiwi_file_watch_fd(const KiwiFileWatch *watch);
int kiwi_file_watch_update(KiwiFileWatch *watch, const char *const *paths, size_t count);
int kiwi_file_watch_take_changes(KiwiFileWatch *watch);
void kiwi_file_watch_destroy(KiwiFileWatch *watch);
]]

local Watch = {}
Watch.__index = Watch

local function arguments(paths)
  assert(type(paths) == "table" and #paths > 0 and #paths <= 16, "configuration watcher needs 1 through 16 paths")
  local pointers = ffi.new("const char *[?]", #paths)
  for index, path in ipairs(paths) do
    assert(type(path) == "string" and #path > 0 and #path <= 4096 and not path:find("\0", 1, true), "invalid configuration watch path")
    pointers[index - 1] = path
  end
  return pointers
end

function Watch.new(native, paths)
  local handle = native.kiwi_file_watch_create(arguments(paths), #paths)
  assert(handle ~= nil, "could not watch configuration files")
  return setmetatable({ native = native, handle = handle, fd = tonumber(native.kiwi_file_watch_fd(handle)),
    signature = table.concat(paths, "\0") }, Watch)
end

function Watch:update(paths)
  local pointers = arguments(paths)
  local signature = table.concat(paths, "\0")
  if self.signature == signature then return true end
  assert(self.native.kiwi_file_watch_update(self.handle, pointers, #paths) ~= 0, "could not update configuration file watches")
  self.signature = signature
  return true
end

function Watch:take_changes()
  local result = self.native.kiwi_file_watch_take_changes(self.handle)
  assert(result >= 0, "configuration file watcher failed")
  return result > 0
end

function Watch:destroy()
  if self.handle == nil then return end
  self.native.kiwi_file_watch_destroy(self.handle)
  self.handle, self.fd = nil, nil
end

return Watch
