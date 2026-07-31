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
}
