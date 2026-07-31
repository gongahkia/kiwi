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
}
