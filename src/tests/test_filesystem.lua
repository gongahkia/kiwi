local Assert = require("tests.assert")
local Filesystem = require("kiwi.platform.filesystem")

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function temporary_directory()
  local handle = assert(io.popen("mktemp -d", "r"))
  local directory = assert(handle:read("*l"))
  assert(handle:close())
  return directory
end

local function remove_directory(path)
  local result = os.execute("rmdir " .. shell_quote(path))
  assert(result == true or result == 0, "could not remove temporary directory: " .. path)
end

return {
  filesystem_exclusively_creates_a_user_configuration_file = function()
    local root = temporary_directory()
    local parent = root .. "/configuration"
    local path = parent .. "/config"
    local ok, message = xpcall(function()
      local created, status = Filesystem.ensure_new_file(path, "# first\n")
      Assert.truthy(created)
      Assert.equal(status, "created")
      local handle = assert(io.open(path, "rb"))
      Assert.equal(handle:read("*a"), "# first\n")
      handle:close()
      local retained, retained_status = Filesystem.ensure_new_file(path, "# replacement\n")
      Assert.truthy(retained)
      Assert.equal(retained_status, "exists")
      handle = assert(io.open(path, "rb"))
      Assert.equal(handle:read("*a"), "# first\n")
      handle:close()
    end, debug.traceback)
    os.remove(path)
    remove_directory(parent)
    remove_directory(root)
    assert(ok, message)
  end,
}
