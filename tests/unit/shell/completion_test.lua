local assertions = require("support.assertions")
local Completion = require("shell.completion")
local Registry = require("shell.registry")
local Session = require("shell.session")
local Tokenizer = require("shell.tokenizer")

local function registry()
  local value = assert(Registry.new())
  for _, name in ipairs({ "beta", "alpha", "alpine", "a b", "show" }) do
    assert(value:register(name, {
      run = function()
        error("completion must not dispatch")
      end,
      summary = name,
    }))
  end
  return value
end

local function apply(bytes, candidate)
  return bytes:sub(1, candidate.replace_start)
    .. candidate.insertion
    .. bytes:sub(candidate.replace_end + 1)
end

local function candidate(result, display)
  for _, value in ipairs(result.candidates) do
    if value.display == display then
      return value
    end
  end
  error("missing candidate " .. display)
end

return {
  {
    name = "sandbox completion scanner preserves byte prefixes through incomplete grammar states",
    run = function()
      local Scanner = require("shell.completion_scanner")
      local scan = assert(Scanner.scan("abc\"def'ghi", 11))
      assertions.equal("abcdef'ghi", scan.active_prefix)
      assertions.equal(0, scan.active_start)
      assertions.equal(1, scan.argument_index)
      assertions.equal("double_quoted", scan.quote_mode)
      assertions.falsy(scan.pending_escape)

      scan = assert(Scanner.scan("'a\\b", 4))
      assertions.equal("a\\b", scan.active_prefix)
      assertions.equal("single_quoted", scan.quote_mode)
      scan = assert(Scanner.scan('"a\\', 3))
      assertions.equal("a", scan.active_prefix)
      assertions.equal("double_quoted", scan.quote_mode)
      assertions.truthy(scan.pending_escape)
      scan = assert(Scanner.scan("a\\", 2))
      assertions.equal("a", scan.active_prefix)
      assertions.equal("unquoted", scan.quote_mode)
      assertions.truthy(scan.pending_escape)
      scan = assert(Scanner.scan('x""y \t', 6))
      assertions.equal(2, scan.argument_index)
      assertions.truthy(scan.between_arguments)
      assertions.equal(6, scan.active_start)
      scan = assert(Scanner.scan("\0\255", 2))
      assertions.equal("\0\255", scan.active_prefix)
    end,
  },
  {
    name = "sandbox completion scanner validates byte cursor and resource limits without dispatch",
    run = function()
      local Scanner = require("shell.completion_scanner")
      local scan, scan_error = Scanner.scan("show", 5)
      assertions.falsy(scan)
      assertions.equal("invalid_cursor_offset", scan_error.detail.reason)
      scan, scan_error = Scanner.scan("show", -1)
      assertions.falsy(scan)
      assertions.equal("invalid_cursor_offset", scan_error.detail.reason)
      scan, scan_error = Scanner.scan("abcd", 4, { max_input_bytes = 3 })
      assertions.falsy(scan)
      assertions.equal("input_too_large", scan_error.detail.reason)
      scan, scan_error = Scanner.scan("abcd", 4, { max_active_prefix_bytes = 3 })
      assertions.falsy(scan)
      assertions.equal("scan_resource_limit", scan_error.detail.reason)
    end,
  },
  {
    name = "sandbox completion returns bytewise sorted registry name edits without fuzzy matching",
    run = function()
      local engine = assert(Completion.new(registry()))
      local result = assert(engine:complete("", 0))
      assertions.equal(5, #result.candidates)
      assertions.equal("a b", result.candidates[1].display)
      assertions.equal("alpha", result.candidates[2].display)
      assertions.equal("alpine", result.candidates[3].display)
      assertions.equal("beta", result.candidates[4].display)
      assertions.equal("show", result.candidates[5].display)
      result = assert(engine:complete("al", 2))
      assertions.equal(2, #result.candidates)
      local applied = apply("al", candidate(result, "alpha"))
      local argv = assert(Tokenizer.tokenize(applied))
      assertions.equal("alpha", argv[1])
      result = assert(engine:complete("pha", 3))
      assertions.equal(0, #result.candidates)
    end,
  },
  {
    name = "sandbox completion replaces complete active arguments at start middle end and quote contexts",
    run = function()
      local engine = assert(Completion.new(registry()))
      local result = assert(engine:complete("alxx", 2))
      local applied = apply("alxx", candidate(result, "alpha"))
      assertions.equal("alpha", assert(Tokenizer.tokenize(applied))[1])
      result = assert(engine:complete('"alxx"', 3))
      applied = apply('"alxx"', candidate(result, "alpha"))
      assertions.equal("alpha", assert(Tokenizer.tokenize(applied))[1])
      result = assert(engine:complete("a\\", 2))
      applied = apply("a\\", candidate(result, "a b"))
      assertions.equal("a b", assert(Tokenizer.tokenize(applied))[1])
      result = assert(engine:complete("show ", 5))
      assertions.equal(0, #result.candidates)
    end,
  },
  {
    name = "sandbox completion rejects candidate-limit failures atomically",
    run = function()
      local command_registry = registry()
      local engine = assert(Completion.new(command_registry, { max_candidates = 1 }))
      local result, completion_error = engine:complete("a", 1)
      assertions.falsy(result)
      assertions.equal("too_many_candidates", completion_error.detail.reason)
      engine = assert(Completion.new(command_registry, { max_candidate_insertion_bytes = 3 }))
      result, completion_error = engine:complete("show", 4)
      assertions.falsy(result)
      assertions.equal("candidate_too_large", completion_error.detail.reason)
      assertions.equal(5, command_registry:status().commands)
    end,
  },
  {
    name = "sandbox completion is session-local non-dispatching and copy-isolated",
    run = function()
      local calls = 0
      local command_registry = assert(Registry.new())
      assert(command_registry:register("show", {
        run = function()
          calls = calls + 1
        end,
        summary = "Show",
      }))
      local session = assert(Session.new(command_registry))
      local first = assert(session:complete("sh", 2))
      assertions.equal(0, calls)
      assertions.equal(0, session:history():length())
      local original_display = first.candidates[1].display
      assert(command_registry:register("shell", {
        run = function() end,
        summary = "Shell",
      }))
      assertions.equal(original_display, first.candidates[1].display)
      first.candidates[1].display = "changed"
      local second = assert(session:complete("sh", 2))
      assertions.equal(2, #second.candidates)
      assertions.equal("shell", second.candidates[1].display)
      assertions.truthy(session:destroy())
      local result, completion_error = session:complete("sh", 2)
      assertions.falsy(result)
      assertions.equal("session_closed", completion_error.detail.reason)
    end,
  },
  {
    name = "sandbox completion invokes bounded command callbacks with immutable requests",
    run = function()
      local command_registry = assert(Registry.new())
      local calls = 0
      local received
      local owned = {
        { category = "value", description = "A value", sort_key = "first", value = "a b" },
        { display = "empty", value = "" },
      }
      assert(command_registry:register("show", {
        complete = function(request)
          received = request
          local writable = pcall(function()
            request.command = "changed"
          end)
          assertions.falsy(writable)
          return owned
        end,
        run = function()
          calls = calls + 1
        end,
        summary = "Show values",
      }))
      local session = assert(Session.new(command_registry))
      local result = assert(session:complete("show a", 6))
      assertions.equal(0, calls)
      assertions.equal(0, session:history():length())
      assertions.equal("show", received.command)
      assertions.equal(1, received.completed_argument_count)
      assertions.equal("show", received.completed_arguments[1])
      assertions.equal("a", received.active_prefix)
      assertions.equal(nil, received.terminal)
      assertions.equal(nil, received.writer)
      assertions.equal(2, #result.candidates)
      assertions.equal("a b", assert(Tokenizer.tokenize(apply("show a", result.candidates[1]))[2]))
      assertions.equal("", assert(Tokenizer.tokenize(apply("show a", result.candidates[2]))[2]))
      owned[1].value = "changed"
      assertions.equal('"a b"', result.candidates[1].insertion)
    end,
  },
  {
    name = "sandbox completion isolates callback capability reentry and validation failures",
    run = function()
      local command_registry = assert(Registry.new())
      assert(command_registry:register("none", {
        run = function() end,
        summary = "No completion",
      }))
      assert(command_registry:register("capability", {
        capabilities = { "completion" },
        run = function() end,
        summary = "Missing completion",
      }))
      assert(command_registry:register("bad", {
        complete = function()
          return { value = "not an array" }
        end,
        run = function() end,
        summary = "Bad completion",
      }))
      assert(command_registry:register("range", {
        complete = function()
          return { { replace_end = 1, replace_start = -1, value = "bad" } }
        end,
        run = function() end,
        summary = "Bad range",
      }))
      assert(command_registry:register("many", {
        complete = function()
          return { "a", "b" }
        end,
        run = function() end,
        summary = "Many values",
      }))
      assert(command_registry:register("throws", {
        complete = function()
          error("failure")
        end,
        run = function() end,
        summary = "Throwing completion",
      }))
      local engine = assert(Completion.new(command_registry, { max_candidates = 1 }))
      local result, completion_error = engine:complete("none value", 10)
      assertions.truthy(result)
      assertions.equal(0, #result.candidates)
      result, completion_error = engine:complete("capability value", 16)
      assertions.falsy(result)
      assertions.equal("unknown_completion_capability", completion_error.detail.reason)
      result, completion_error = engine:complete("bad value", 9)
      assertions.falsy(result)
      assertions.equal("invalid_callback_return", completion_error.detail.reason)
      result, completion_error = engine:complete("range value", 11)
      assertions.falsy(result)
      assertions.equal("invalid_replacement_range", completion_error.detail.reason)
      result, completion_error = engine:complete("many value", 10)
      assertions.falsy(result)
      assertions.equal("too_many_candidates", completion_error.detail.reason)
      result, completion_error = engine:complete("throws value", 12)
      assertions.falsy(result)
      assertions.equal("callback_failure", completion_error.detail.reason)
      result = assert(engine:complete("unknown value", 13))
      assertions.equal(0, #result.candidates)

      local reentrant_engine
      assert(command_registry:register("reenter", {
        complete = function()
          return reentrant_engine:complete("reenter value", 13)
        end,
        run = function() end,
        summary = "Reentrant completion",
      }))
      reentrant_engine = assert(Completion.new(command_registry))
      result, completion_error = reentrant_engine:complete("reenter value", 13)
      assertions.falsy(result)
      assertions.equal("reentrant_completion_call", completion_error.detail.reason)
      result = assert(reentrant_engine:complete("none value", 10))
      assertions.equal(0, #result.candidates)

      assert(command_registry:register("dupe", {
        complete = function()
          return { "x", "x", { display = "X", value = "x" } }
        end,
        run = function() end,
        summary = "Duplicate completion",
      }))
      local dedupe_engine = assert(Completion.new(command_registry))
      result = assert(dedupe_engine:complete("dupe ", 5))
      assertions.equal(2, #result.candidates)
      assertions.equal("x", result.candidates[1].display)
      assertions.equal("X", result.candidates[2].display)
    end,
  },
}
