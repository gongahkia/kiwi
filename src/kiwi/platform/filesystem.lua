local ffi = require("ffi")

ffi.cdef[[
int mkdir(const char *path, unsigned int mode);
int open(const char *path, int flags, ...);
long write(int file_descriptor, const void *buffer, unsigned long count);
int fsync(int file_descriptor);
int close(int file_descriptor);
int unlink(const char *path);
]]

local Filesystem = {}

Filesystem.maximum_path_bytes = 4096

local errno_exists = 17
local open_write_only = 1
local open_create = ffi.os == "OSX" and 0x0200 or 0x0040
local open_exclusive = ffi.os == "OSX" and 0x0800 or 0x0080
local file_mode_user_read_write = ffi.new("int", 0x180)

local function valid_path(path)
  return type(path) == "string" and path:sub(1, 1) == "/" and #path <= Filesystem.maximum_path_bytes
    and not path:find("\0", 1, true)
end

local function parent_directories(path)
  local parent = path:match("^(.*)/[^/]+$")
  if parent == nil or parent == "" or parent == "/" then return {} end
  local directories = {}
  local current = ""
  for component in parent:gmatch("[^/]+") do
    current = current .. "/" .. component
    directories[#directories + 1] = current
  end
  return directories
end

local function system_mkdir(path)
  if ffi.C.mkdir(path, 0x1c0) == 0 or ffi.errno() == errno_exists then return true end
  return false, "mkdir failed for " .. path .. " (errno " .. ffi.errno() .. ")"
end

local function system_create(path, contents)
  local descriptor = ffi.C.open(path, open_write_only + open_create + open_exclusive, file_mode_user_read_write)
  if descriptor < 0 then
    if ffi.errno() == errno_exists then return true, "exists" end
    return false, "exclusive create failed for " .. path .. " (errno " .. ffi.errno() .. ")"
  end
  local written = 0
  local source = ffi.cast("const unsigned char *", contents)
  while written < #contents do
    local count = ffi.C.write(descriptor, source + written, #contents - written)
    if count <= 0 then
      local error_number = ffi.errno()
      ffi.C.close(descriptor)
      ffi.C.unlink(path)
      return false, "write failed for " .. path .. " (errno " .. error_number .. ")"
    end
    written = written + tonumber(count)
  end
  if ffi.C.fsync(descriptor) ~= 0 then
    local error_number = ffi.errno()
    ffi.C.close(descriptor)
    ffi.C.unlink(path)
    return false, "sync failed for " .. path .. " (errno " .. error_number .. ")"
  end
  if ffi.C.close(descriptor) ~= 0 then
    local error_number = ffi.errno()
    ffi.C.unlink(path)
    return false, "close failed for " .. path .. " (errno " .. error_number .. ")"
  end
  return true, "created"
end

local system_operations = {
  create = system_create,
  mkdir = system_mkdir,
}

function Filesystem.ensure_new_file(path, contents, operations)
  assert(valid_path(path), "configuration path must be an absolute NUL-free path within " .. Filesystem.maximum_path_bytes .. " bytes")
  assert(type(contents) == "string" and not contents:find("\0", 1, true), "configuration template must be a NUL-free string")
  operations = operations or system_operations
  assert(type(operations.mkdir) == "function" and type(operations.create) == "function", "configuration filesystem operations are incomplete")
  for _, directory in ipairs(parent_directories(path)) do
    local created, reason = operations.mkdir(directory)
    if not created then return false, reason end
  end
  return operations.create(path, contents)
end

return Filesystem
