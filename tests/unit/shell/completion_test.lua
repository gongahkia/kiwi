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
}
