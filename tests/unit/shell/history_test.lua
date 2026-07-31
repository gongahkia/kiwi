local assertions = require("support.assertions")
local History = require("shell.history")
local Registry = require("shell.registry")
local Session = require("shell.session")

local function registry()
  local value = assert(Registry.new())
  assert(value:register("show", {
    run = function() end,
    summary = "Show status",
  }))
  assert(value:register("fail", {
    run = function()
      error("failure")
    end,
    summary = "Fail status",
  }))
  assert(value:register("wait", {
    run = function(_, _, writer)
      assert(writer:emit("queued"))
    end,
    summary = "Wait status",
  }))
  return value
end

return {
  {
    name = "sandbox history stores isolated FIFO byte entries and bounded copies",
    run = function()
      local history = assert(History.new({
        max_entries = 3,
        max_entry_bytes = 4,
        max_retained_bytes = 8,
      }))
      local first = "one"
      assert(history:append(first))
      first = "changed"
      assert(history:append("one"))
      assert(history:append("\0\255"))
      assertions.equal(3, history:length())
      assertions.equal("one", assert(history:get(1)))
      assertions.equal("one", assert(history:get(2)))
      assertions.equal("\0\255", assert(history:get(3)))
      local entries = assert(history:list({ max_entries = 2, offset = 2 }))
      entries[1] = "changed"
      assertions.equal("one", assert(history:get(2)))
      assertions.equal(8, history:status().retained_bytes)
    end,
  },
  {
    name = "sandbox history evicts the deterministic minimum oldest entries",
    run = function()
      local history = assert(History.new({
        max_entries = 2,
        max_entry_bytes = 4,
        max_retained_bytes = 8,
      }))
      assert(history:append("a"))
      assert(history:append("b"))
      assert(history:append("c"))
      assertions.equal("b", assert(history:get(1)))
      assertions.equal("c", assert(history:get(2)))

      history = assert(History.new({
        max_entries = 4,
        max_entry_bytes = 4,
        max_retained_bytes = 6,
      }))
      assert(history:append("aa"))
      assert(history:append("bb"))
      assert(history:append("cc"))
      assert(history:append("ddd"))
      assertions.equal(2, history:length())
      assertions.equal("cc", assert(history:get(1)))
      assertions.equal("ddd", assert(history:get(2)))
      assertions.equal(5, history:status().retained_bytes)
    end,
  },
  {
    name = "sandbox history rejects oversized admission without retaining partial entries",
    run = function()
      local history = assert(History.new({
        max_entries = 2,
        max_entry_bytes = 3,
        max_retained_bytes = 4,
      }))
      assert(history:append("ok"))
      local admitted, admission_error = history:append("long")
      assertions.falsy(admitted)
      assertions.equal("sandbox_command_error", admission_error.kind)
      assertions.equal("history_entry_too_large", admission_error.detail.reason)
      assertions.equal(1, history:length())
      assertions.equal("ok", assert(history:get(1)))
      assertions.truthy(history:clear())
      assertions.truthy(history:clear())
      assertions.equal(0, history:length())

      local disabled = assert(History.new({
        max_entries = 0,
        max_entry_bytes = 0,
        max_retained_bytes = 0,
      }))
      assertions.truthy(disabled:status().disabled)
      assertions.equal(0, #assert(disabled:list()))
    end,
  },
  {
    name = "sandbox sessions admit only valid non-empty submissions before dispatch outcomes",
    run = function()
      local session = assert(Session.new(registry()))
      assert(session:dispatch(" \t "))
      assertions.equal(0, session:history():length())
      assert(session:dispatch("show \0\255"))
      assertions.equal("show \0\255", assert(session:history():get(1)))
      local outcome, unknown_error = session:dispatch("unknown command")
      assertions.falsy(outcome)
      assertions.equal("sandbox_command_error", unknown_error.kind)
      assertions.equal("unknown command", assert(session:history():get(2)))
      outcome, unknown_error = session:dispatch("show 'unterminated")
      assertions.falsy(outcome)
      assertions.equal("unterminated_single_quote", unknown_error.detail.reason)
      assertions.equal(2, session:history():length())
      local failed = assert(session:dispatch("fail"))
      assertions.truthy(failed.failed)
      assertions.equal("fail", assert(session:history():get(3)))
      local cancelled = assert(session:dispatch("wait"))
      assert(cancelled.invocation:cancel())
      assertions.equal("wait", assert(session:history():get(4)))
    end,
  },
  {
    name = "sandbox session history admission diagnostics and lifecycle do not alter dispatch",
    run = function()
      local command_registry = registry()
      local first = assert(Session.new(command_registry, {
        history_limits = {
          max_entries = 2,
          max_entry_bytes = 4,
          max_retained_bytes = 8,
        },
      }))
      local second = assert(Session.new(command_registry))
      local outcome = assert(first:dispatch("show long"))
      assertions.truthy(outcome.dispatched)
      assertions.equal(0, first:history():length())
      assertions.equal("history_entry_too_large", outcome.history_diagnostic.detail.reason)
      assert(first:dispatch("show"))
      assert(first:dispatch("show"))
      assertions.equal("show", assert(first:history():get(1)))
      assertions.equal("show", assert(first:history():get(2)))
      assert(second:dispatch("show"))
      assertions.equal(1, second:history():length())
      assert(first:reset_history())
      assertions.equal(0, first:history():length())
      assertions.equal(1, second:history():length())
      assertions.truthy(command_registry:command("show"))
      assertions.truthy(first:destroy())
      assertions.truthy(first:destroy())
      assertions.equal(0, first:history():length())
      local destroyed, destroyed_error = first:dispatch("show")
      assertions.falsy(destroyed)
      assertions.equal("session_closed", destroyed_error.detail.reason)
    end,
  },
  {
    name = "sandbox session capability dispatch supplies only declared virtual filesystem operations",
    run = function()
      local command_registry = assert(Registry.new())
      local seen = {}
      assert(command_registry:register("none", {
        run = function(context)
          seen.no_facade = context.fs
        end,
        summary = "No filesystem",
      }))
      assert(command_registry:register("read", {
        capabilities = { "vfs.read" },
        run = function(context)
          seen.read_data = context.fs:read_file("/note")
          seen.read_write = context.fs.write_file
          seen.read_cwd = context.fs:get_cwd()
        end,
        summary = "Read filesystem",
      }))
      assert(command_registry:register("write", {
        capabilities = { "vfs.write" },
        run = function(context)
          seen.write_read = context.fs.read_file
          assert(context.fs:write_file("/written", "ok"))
        end,
        summary = "Write filesystem",
      }))
      assert(command_registry:register("cd", {
        capabilities = { "vfs.chdir" },
        run = function(context)
          seen.chdir_read = context.fs.read_file
          assert(context.fs:change_directory("/work"))
        end,
        summary = "Change directory",
      }))
      local session = assert(Session.new(command_registry, {
        filesystem = {
          initial_tree = {
            entries = {
              note = { data = "seed", kind = "file" },
              work = { entries = {}, kind = "directory" },
            },
            kind = "directory",
          },
        },
        granted_capabilities = { "vfs.read", "vfs.write", "vfs.chdir" },
      }))
      assert(session:dispatch("none", { fs = "host filesystem" }))
      assertions.equal(nil, seen.no_facade)
      assert(session:dispatch("read"))
      assertions.equal("seed", seen.read_data)
      assertions.equal(nil, seen.read_write)
      assertions.equal("/", seen.read_cwd)
      assert(session:dispatch("write"))
      assertions.equal(nil, seen.write_read)
      assert(session:dispatch("cd"))
      assertions.equal(nil, seen.chdir_read)
      local other = assert(Session.new(command_registry, { granted_capabilities = { "vfs.read" } }))
      assert(other:dispatch("read"))
      assertions.equal(nil, seen.read_data)
      assertions.equal("/", other:status().filesystem.cwd)
      assertions.equal("/work", session:status().filesystem.cwd)
    end,
  },
  {
    name = "sandbox virtual filesystem grants deny before handlers and expire after invocation",
    run = function()
      local command_registry = assert(Registry.new())
      local called = false
      local retained
      assert(command_registry:register("read", {
        capabilities = { "vfs.read" },
        run = function(context)
          called = true
          retained = context.fs
          assert(context.fs:stat("/"))
        end,
        summary = "Read filesystem",
      }))
      local denied_session = assert(Session.new(command_registry))
      local denied, denied_error = denied_session:dispatch("read")
      assertions.falsy(denied)
      assertions.equal("capability_denied", denied_error.detail.reason)
      assertions.falsy(called)
      assertions.equal("read", assert(denied_session:history():get(1)))
      local allowed_session = assert(Session.new(command_registry, {
        granted_capabilities = { "vfs.read" },
      }))
      assert(allowed_session:dispatch("read"))
      assertions.truthy(called)
      local later, later_error = retained:stat("/")
      assertions.falsy(later)
      assertions.equal("capability_denied", later_error.detail.reason)
      assertions.truthy(allowed_session:destroy())
      assertions.equal(0, allowed_session:status().filesystem.nodes)
    end,
  },
  {
    name = "sandbox filesystem capability and completion isolation preserve independent session state",
    run = function()
      local command_registry = assert(Registry.new())
      local completion_request
      assert(command_registry:register("edit", {
        capabilities = { "completion", "vfs.write" },
        complete = function(request)
          completion_request = request
          return { "value" }
        end,
        run = function(context)
          assert(context.fs:write_file("/entry", "first"))
        end,
        summary = "Edit filesystem",
      }))
      local first = assert(Session.new(command_registry, {
        granted_capabilities = { "completion", "vfs.write" },
      }))
      local second = assert(Session.new(command_registry, {
        granted_capabilities = { "completion", "vfs.write" },
      }))
      local completion = assert(first:complete("edit va", 7))
      assertions.equal("value", completion.candidates[1].display)
      assertions.equal(nil, completion_request.fs)
      assert(first:dispatch("edit"))
      assert(second:dispatch("edit"))
      assertions.equal(2, first:status().filesystem.nodes)
      assertions.equal(2, second:status().filesystem.nodes)
      assertions.equal("edit", assert(first:history():get(1)))
      assertions.equal("edit", assert(second:history():get(1)))
    end,
  },
}
