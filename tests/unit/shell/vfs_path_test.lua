local assertions = require("support.assertions")
local Path = require("shell.vfs_path")

local function components(...)
  return { ... }
end

local function assert_path(path, cwd, expected, trailing_slash)
  local resolved, resolve_error = Path.resolve(path, cwd)
  assertions.falsy(resolve_error)
  assertions.equal(expected, resolved.canonical_path)
  assertions.equal(trailing_slash, resolved.trailing_slash)
end

local function assert_error(path, cwd, reason, limits)
  local resolved, resolve_error = Path.resolve(path, cwd, limits)
  assertions.falsy(resolved)
  assertions.equal("sandbox_command_error", resolve_error.kind)
  assertions.equal(reason, resolve_error.detail.reason)
end

return {
  {
    name = "virtual filesystem paths resolve absolute relative dot and root-clamped components",
    run = function()
      local cwd = components("work", "src")
      assert_path("/", cwd, "/", false)
      assert_path("/a//b/./c", cwd, "/a/b/c", false)
      assert_path("../test", cwd, "/work/test", false)
      assert_path("../../../../x", cwd, "/x", false)
      assert_path(".", cwd, "/work/src", false)
      assert_path("/..", cwd, "/", false)
      assert_path("/a/b/../c", cwd, "/a/c", false)
    end,
  },
  {
    name = "virtual filesystem paths preserve trailing directory requirements and opaque bytes",
    run = function()
      local cwd = components("work")
      assert_path("dir///", cwd, "/work/dir", true)
      assert_path("///", cwd, "/", false)
      assert_path("\255 \t$*", cwd, "/work/\255 \t$*", false)
      assert_error("", cwd, "empty_path")
      assert_error("a\0b", cwd, "invalid_path_byte")
    end,
  },
  {
    name = "virtual filesystem path limits reject before canonical path mutation",
    run = function()
      local cwd = components("work")
      assert_error("abcd", cwd, "path_too_large", { max_path_bytes = 3 })
      assert_error("abcd", cwd, "component_too_large", { max_component_bytes = 3 })
      assert_error("a/b", cwd, "too_many_components", { max_path_components = 2 })
      assert_error("abcd", {}, "path_too_large", { max_canonical_path_bytes = 3 })
    end,
  },
  {
    name = "virtual filesystem path results do not retain caller component tables",
    run = function()
      local cwd = components("work")
      local resolved = assert(Path.resolve("src", cwd))
      cwd[1] = "changed"
      resolved.components[1] = "changed"
      assertions.equal("/work/src", resolved.canonical_path)
      assertions.equal("work", assert(Path.resolve(".", components("work"))).components[1])
    end,
  },
}
