local assertions = require("support.assertions")
local Builtins = require("shell.builtins")
local Registry = require("shell.registry")
local Session = require("shell.session")

local expected = {
  { name = "help", usage = "usage: help [COMMAND]" },
  { capability = "vfs.read", name = "pwd", usage = "usage: pwd" },
  { capability = "vfs.read", name = "ls", usage = "usage: ls [PATH]" },
  { capability = "vfs.read", name = "cat", usage = "usage: cat PATH" },
  { capability = "vfs.write", name = "write", usage = "usage: write PATH DATA" },
  { capability = "vfs.write", name = "mkdir", usage = "usage: mkdir PATH" },
  { capability = "vfs.write", name = "rm", usage = "usage: rm PATH" },
  { capability = "vfs.write", name = "mv", usage = "usage: mv SOURCE DESTINATION" },
  { capability = "vfs.chdir", name = "cd", usage = "usage: cd PATH" },
}

local function session(registry, configuration)
  configuration = configuration or {}
  if configuration.granted_capabilities == nil then
    configuration.granted_capabilities = { "vfs.read", "vfs.write", "vfs.chdir" }
  end
  return assert(Session.new(registry, configuration))
end

local function output(outcome)
  local result = {}
  while outcome.invocation:status().queued_chunks > 0 do
    result[#result + 1] = assert(outcome.invocation:poll()).events[1].data
  end
  return table.concat(result)
end

return {
  {
    name = "sandbox built-ins register fixed metadata through the normal registry",
    run = function()
      local registry = assert(Registry.new())
      assertions.truthy(Builtins.register(registry))
      local names = Builtins.names()
      local commands = registry:commands()
      assertions.equal(9, #names)
      assertions.equal(9, #commands)
      for index, value in ipairs(expected) do
        assertions.equal(value.name, names[index])
        assertions.equal(value.name, commands[index].name)
        assertions.equal(value.usage, commands[index].usage)
        if value.capability then
          assertions.equal(value.capability, commands[index].capabilities[1])
        else
          assertions.equal(0, #commands[index].capabilities)
        end
      end
      commands[1].usage = "changed"
      assertions.equal(expected[1].usage, assert(registry:describe("help")).usage)
    end,
  },
  {
    name = "sandbox built-in duplicate registration follows registry validation",
    run = function()
      local registry = assert(Registry.new())
      assertions.truthy(Builtins.register(registry))
      local registered, registration_error = Builtins.register(registry)
      assertions.falsy(registered)
      assertions.equal("sandbox_command_error", registration_error.kind)
      assertions.equal(9, registry:status().commands)
    end,
  },
  {
    name = "sandbox registry validates and isolates optional command usage metadata",
    run = function()
      local registry = assert(Registry.new())
      assert(registry:register("custom", {
        run = function() end,
        summary = "Custom command",
        usage = "usage: custom VALUE",
      }))
      local description = assert(registry:describe("custom"))
      assertions.equal("usage: custom VALUE", description.usage)
      assertions.equal(nil, description.run)
      local command, command_error = registry:register("invalid", {
        run = function() end,
        summary = "Invalid command",
        usage = "",
      })
      assertions.falsy(command)
      assertions.equal("sandbox_command_error", command_error.kind)
    end,
  },
  {
    name = "sandbox built-in help lists bytewise metadata without dispatching targets",
    run = function()
      local registry = assert(Registry.new())
      assertions.truthy(Builtins.register(registry))
      local calls = 0
      assert(registry:register("\255", {
        run = function()
          calls = calls + 1
        end,
        summary = "Opaque command",
        usage = "usage: \255",
      }))
      local sandbox = session(registry)
      local listing = assert(sandbox:dispatch("help"))
      assertions.equal("cat\ncd\nhelp\nls\nmkdir\nmv\npwd\nrm\nwrite\n\255\n", output(listing))
      local details = assert(sandbox:dispatch('help "\255"'))
      assertions.equal("usage: \255\nOpaque command\n", output(details))
      assertions.equal(0, calls)
      local unknown = assert(sandbox:dispatch("help missing"))
      assertions.truthy(unknown.failed)
      assertions.equal("unknown_command", unknown.failure.detail.reason)
      local invalid = assert(sandbox:dispatch("help one two"))
      assertions.truthy(invalid.failed)
      assertions.equal("invalid_argument_count", invalid.failure.detail.reason)
      assertions.equal("usage: help [COMMAND]\n", output(invalid))
    end,
  },
  {
    name = "sandbox read-only built-ins emit canonical byte-preserving filesystem views",
    run = function()
      local registry = assert(Registry.new())
      assertions.truthy(Builtins.register(registry))
      local sandbox = session(registry, {
        filesystem = {
          cwd = "/work",
          initial_tree = {
            entries = {
              work = {
                entries = {
                  a = { entries = {}, kind = "directory" },
                  b = { data = "b\0\255", kind = "file" },
                  empty = { data = "", kind = "file" },
                },
                kind = "directory",
              },
            },
            kind = "directory",
          },
        },
      })
      assertions.equal("/work\n", output(assert(sandbox:dispatch("pwd"))))
      assertions.equal("a/\nb\nempty\n", output(assert(sandbox:dispatch("ls"))))
      assertions.equal("b\n", output(assert(sandbox:dispatch("ls b"))))
      assertions.equal("b\0\255", output(assert(sandbox:dispatch("cat b"))))
      assertions.equal("", output(assert(sandbox:dispatch("cat empty"))))
      local invalid = assert(sandbox:dispatch("cat"))
      assertions.truthy(invalid.failed)
      assertions.equal("invalid_argument_count", invalid.failure.detail.reason)
      assertions.equal("usage: cat PATH\n", output(invalid))
    end,
  },
  {
    name = "sandbox read-only built-ins preserve capability and bounded output failures",
    run = function()
      local registry = assert(Registry.new())
      assertions.truthy(Builtins.register(registry))
      local denied = session(registry, { granted_capabilities = {} })
      local outcome, capability_error = denied:dispatch("pwd")
      assertions.falsy(outcome)
      assertions.equal("capability_denied", capability_error.detail.reason)
      local bounded = session(registry, {
        filesystem = {
          initial_tree = {
            entries = {
              a = { data = "a", kind = "file" },
              b = { data = "b", kind = "file" },
            },
            kind = "directory",
          },
        },
        output_limits = {
          max_drain_bytes = 8,
          max_output_events = 1,
          max_queued_bytes = 8,
          max_queued_chunks = 1,
          max_write_bytes = 8,
        },
      })
      local overflow = assert(bounded:dispatch("ls"))
      assertions.truthy(overflow.failed)
      assertions.equal("output_overflow", overflow.failure.detail.reason)
      assertions.equal("a\n", output(overflow))
    end,
  },
  {
    name = "sandbox mutating built-ins use exact arguments and atomic virtual filesystem operations",
    run = function()
      local registry = assert(Registry.new())
      assertions.truthy(Builtins.register(registry))
      local sandbox = session(registry)
      local created = assert(sandbox:dispatch('write /note "first value"'))
      assertions.equal(0, created.invocation:status().queued_chunks)
      assertions.equal("first value", output(assert(sandbox:dispatch("cat /note"))))
      assert(sandbox:dispatch('write /note ""'))
      assertions.equal("", output(assert(sandbox:dispatch("cat /note"))))
      assert(sandbox:dispatch("mkdir /work"))
      assert(sandbox:dispatch("mkdir /work/src"))
      assert(sandbox:dispatch("write /work/src/readme bytes"))
      assert(sandbox:dispatch("mv /work/src/readme /work/src/guide"))
      assertions.equal("bytes", output(assert(sandbox:dispatch("cat /work/src/guide"))))
      assert(sandbox:dispatch("cd /work/src"))
      assertions.equal("/work/src\n", output(assert(sandbox:dispatch("pwd"))))
      assert(sandbox:dispatch("rm guide"))
      assert(sandbox:dispatch("cd /"))
      assert(sandbox:dispatch("rm /work/src"))
      assert(sandbox:dispatch("rm /work"))
    end,
  },
  {
    name = "sandbox mutating built-ins reject invalid usage and preserve virtual filesystem failures",
    run = function()
      local registry = assert(Registry.new())
      assertions.truthy(Builtins.register(registry))
      local sandbox = session(registry)
      assert(sandbox:dispatch("write /note original"))
      local invalid = assert(sandbox:dispatch("write /note changed extra"))
      assertions.truthy(invalid.failed)
      assertions.equal("invalid_argument_count", invalid.failure.detail.reason)
      assertions.equal("usage: write PATH DATA\n", output(invalid))
      assertions.equal("original", output(assert(sandbox:dispatch("cat /note"))))
      local missing_parent = assert(sandbox:dispatch("mkdir /missing/child"))
      assertions.truthy(missing_parent.failed)
      assertions.equal("not_found", missing_parent.failure.detail.reason)
      assert(sandbox:dispatch("mkdir /a"))
      assert(sandbox:dispatch("write /a/file bytes"))
      local nonempty = assert(sandbox:dispatch("rm /a"))
      assertions.truthy(nonempty.failed)
      assertions.equal("directory_not_empty", nonempty.failure.detail.reason)
      assert(sandbox:dispatch("write /target target"))
      local replacement = assert(sandbox:dispatch("mv /a/file /target"))
      assertions.truthy(replacement.failed)
      assertions.equal("already_exists", replacement.failure.detail.reason)
      assertions.equal("bytes", output(assert(sandbox:dispatch("cat /a/file"))))
      for _, command in ipairs({ "mkdir", "rm", "cd" }) do
        local invalid_count = assert(sandbox:dispatch(command))
        assertions.truthy(invalid_count.failed)
        assertions.equal("invalid_argument_count", invalid_count.failure.detail.reason)
      end
      local invalid_mv = assert(sandbox:dispatch("mv /a/file"))
      assertions.truthy(invalid_mv.failed)
      assertions.equal("invalid_argument_count", invalid_mv.failure.detail.reason)
    end,
  },
}
