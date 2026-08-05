local assertions = require("support.assertions")
local VirtualFS = require("shell.virtual_fs")

local function fs(options)
  return assert(VirtualFS.new(options))
end

local function assert_error(call, reason)
  local result, call_error = call()
  assertions.falsy(result)
  assertions.equal("sandbox_command_error", call_error.kind)
  assertions.equal(reason, call_error.detail.reason)
end

return {
  {
    name = "virtual filesystem deep-copies bounded initial trees and sessions remain isolated",
    run = function()
      local initial = {
        entries = {
          work = { entries = { note = { data = "original", kind = "file" } }, kind = "directory" },
        },
        kind = "directory",
      }
      local first = fs({ cwd = "/work", initial_tree = initial })
      local second = fs()
      initial.entries.work.entries.note.data = "changed"
      assertions.equal("original", assert(first:read_file("note")))
      assert_error(function()
        return second:stat("/work")
      end, "not_found")
      assertions.equal("/work", assert(first:get_cwd()))
      assertions.equal("/", assert(second:get_cwd()))
    end,
  },
  {
    name = "virtual filesystem stat list read and cwd use canonical opaque byte paths",
    run = function()
      local filesystem = fs({
        initial_tree = {
          entries = {
            ["\255"] = { data = "\0bytes", kind = "file" },
            a = { entries = { z = { data = "z", kind = "file" } }, kind = "directory" },
            b = { data = "b", kind = "file" },
          },
          kind = "directory",
        },
      })
      local root = assert(filesystem:stat("/"))
      assertions.equal("directory", root.kind)
      assertions.equal(3, root.child_count)
      local names = assert(filesystem:list("/"))
      assertions.equal("a", names[1])
      assertions.equal("b", names[2])
      assertions.equal("\255", names[3])
      names[1] = "changed"
      assertions.equal("a", assert(filesystem:list("/"))[1])
      assertions.equal("\0bytes", assert(filesystem:read_file("/\255")))
      assertions.truthy(filesystem:change_directory("/a//./"))
      assertions.equal("/a", assert(filesystem:get_cwd()))
      assertions.equal("z", assert(filesystem:read_file("./z")))
      assert_error(function()
        return filesystem:read_file("/b/")
      end, "not_a_directory")
      assert_error(function()
        return filesystem:list("/b")
      end, "not_a_directory")
    end,
  },
  {
    name = "virtual filesystem enforces initial tree and returned resource bounds without retaining invalid state",
    run = function()
      local too_large, large_error = VirtualFS.new({
        initial_tree = { entries = { a = { data = "abcd", kind = "file" } }, kind = "directory" },
        limits = { max_file_bytes = 3 },
      })
      assertions.falsy(too_large)
      assertions.equal("file_too_large", large_error.detail.reason)
      local filesystem = fs({
        initial_tree = { entries = { a = { data = "abcd", kind = "file" } }, kind = "directory" },
        limits = { max_returned_bytes = 3 },
      })
      assert_error(function()
        return filesystem:read_file("/a")
      end, "resource_limit")
      assertions.equal(2, filesystem:status().nodes)
      assert_error(function()
        return filesystem:read_file("/a", { offset = 5 })
      end, "invalid_range")
    end,
  },
  {
    name = "virtual filesystem destroy releases retained resources idempotently",
    run = function()
      local filesystem = fs({
        initial_tree = { entries = { a = { data = "bytes", kind = "file" } }, kind = "directory" },
      })
      assertions.equal(5, filesystem:status().retained_file_bytes)
      assertions.truthy(filesystem:destroy())
      assertions.truthy(filesystem:destroy())
      assertions.equal(0, filesystem:status().retained_file_bytes)
      assert_error(function()
        return filesystem:stat("/")
      end, "filesystem_closed")
    end,
  },
  {
    name = "virtual filesystem atomically creates overwrites appends and removes regular files",
    run = function()
      local filesystem = fs()
      assertions.truthy(filesystem:write_file("/note", "one"))
      assertions.equal("one", assert(filesystem:read_file("/note")))
      assertions.equal(3, assert(filesystem:stat("/note")).byte_length)
      assertions.truthy(filesystem:write_file("/note", "two"))
      assertions.truthy(filesystem:append_file("/note", "\0\255"))
      assertions.equal("two\0\255", assert(filesystem:read_file("/note")))
      assertions.equal("wo", assert(filesystem:read_file("/note", { length = 2, offset = 1 })))
      assertions.truthy(filesystem:append_file("/note", ""))
      assertions.truthy(filesystem:remove("/note"))
      assert_error(function()
        return filesystem:read_file("/note")
      end, "not_found")
      assert_error(function()
        return filesystem:append_file("/note", "x")
      end, "not_found")
      assert_error(function()
        return filesystem:write_file("/new/", "x")
      end, "not_a_directory")
    end,
  },
  {
    name = "virtual filesystem directory operations preserve cwd through ancestor rename",
    run = function()
      local filesystem = fs()
      assertions.truthy(filesystem:make_directory("/work/"))
      assertions.truthy(filesystem:make_directory("/work/src"))
      assertions.truthy(filesystem:change_directory("/work/src"))
      assertions.truthy(filesystem:write_file("readme", "v1"))
      assertions.truthy(filesystem:rename("/work", "/project"))
      assertions.equal("/project/src", assert(filesystem:get_cwd()))
      assertions.equal("v1", assert(filesystem:read_file("readme")))
      assert_error(function()
        return filesystem:remove("/project")
      end, "cwd_operation_forbidden")
      assertions.truthy(filesystem:change_directory("/"))
      assert_error(function()
        return filesystem:remove("/project")
      end, "directory_not_empty")
      assertions.truthy(filesystem:remove("/project/src/readme"))
      assertions.truthy(filesystem:remove("/project/src"))
      assertions.truthy(filesystem:remove("/project"))
      assert_error(function()
        return filesystem:remove("/")
      end, "root_operation_forbidden")
      assert_error(function()
        return filesystem:rename("/", "/other")
      end, "root_operation_forbidden")
    end,
  },
  {
    name = "virtual filesystem rejects invalid mutations without changing accounting or data",
    run = function()
      local filesystem = fs({
        initial_tree = { entries = { file = { data = "abc", kind = "file" } }, kind = "directory" },
        limits = { max_file_bytes = 4, max_total_file_bytes = 4 },
      })
      local before = filesystem:status()
      assert_error(function()
        return filesystem:append_file("/file", "de")
      end, "file_too_large")
      assertions.equal("abc", assert(filesystem:read_file("/file")))
      assertions.equal(before.retained_file_bytes, filesystem:status().retained_file_bytes)
      assert_error(function()
        return filesystem:write_file("/file", "abcde")
      end, "file_too_large")
      assertions.equal("abc", assert(filesystem:read_file("/file")))
      assertions.truthy(filesystem:write_file("/file", "abcd"))
      assertions.equal(4, filesystem:status().retained_file_bytes)
      assert_error(function()
        return filesystem:write_file("/other", "x")
      end, "filesystem_full")
      assertions.equal(2, filesystem:status().nodes)
      assertions.equal("abcd", assert(filesystem:read_file("/file")))
    end,
  },
  {
    name = "virtual filesystem rename rejects replacement self moves and directory capacity failures atomically",
    run = function()
      local filesystem = fs()
      assertions.truthy(filesystem:make_directory("/a"))
      assertions.truthy(filesystem:make_directory("/a/b"))
      assertions.truthy(filesystem:write_file("/target", "x"))
      assert_error(function()
        return filesystem:rename("/a", "/a/b/a")
      end, "invalid_move")
      assert_error(function()
        return filesystem:rename("/a", "/target")
      end, "already_exists")
      assertions.equal("directory", assert(filesystem:stat("/a")).kind)
      assertions.equal("directory", assert(filesystem:stat("/a/b")).kind)
      local constrained = fs({ limits = { max_directory_entries = 2 } })
      assertions.truthy(constrained:make_directory("/a"))
      assertions.truthy(constrained:make_directory("/a/b"))
      assertions.truthy(constrained:make_directory("/a/c"))
      assertions.truthy(constrained:make_directory("/d"))
      assert_error(function()
        return constrained:rename("/d", "/a/d")
      end, "directory_full")
      assertions.equal("directory", assert(constrained:stat("/d")).kind)
    end,
  },
}
