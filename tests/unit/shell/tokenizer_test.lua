local assertions = require("support.assertions")
local Tokenizer = require("shell.tokenizer")

local function assert_argv(input, expected, limits)
  local argv, token_error = Tokenizer.tokenize(input, limits)
  assertions.falsy(token_error)
  assertions.equal(#expected, #argv)
  for index, value in ipairs(expected) do
    assertions.equal(value, argv[index], "argument " .. index)
  end
end

local function assert_error(input, reason, state, offset, limits)
  local argv, token_error = Tokenizer.tokenize(input, limits)
  assertions.falsy(argv)
  assertions.equal("sandbox_command_error", token_error.kind)
  assertions.equal(reason, token_error.detail.reason)
  assertions.equal(state, token_error.detail.state)
  assertions.equal(offset, token_error.detail.byte_offset)
end

return {
  {
    name = "sandbox tokenizer ignores only leading trailing and repeated space tab delimiters",
    run = function()
      assert_argv("", {})
      assert_argv(" \t \t", {})
      assert_argv("\t  status\t\t--brief  ", { "status", "--brief" })
      assert_argv("one\ntwo", { "one\ntwo" })
    end,
  },
  {
    name = "sandbox tokenizer preserves quoted and escaped byte fragments",
    run = function()
      assert_argv("status", { "status" })
      assert_argv("'single quoted' \"double quoted\"", { "single quoted", "double quoted" })
      assert_argv("a\\ b a\\\tb", { "a b", "a\tb" })
      assert_argv('a\\"b a\\\\b "a\\"b" \'a\\b\'', { 'a"b', "a\\b", 'a"b', "a\\b" })
      assert_argv("a\\nb", { "anb" })
      assert_argv("'a\\' b", { "a\\", "b" })
    end,
  },
  {
    name = "sandbox tokenizer concatenates adjacent fragments including empty quoted arguments",
    run = function()
      assert_argv("abc\"def\"'ghi'", { "abcdefghi" })
      assert_argv('"" \'\' x""y', { "", "", "xy" })
      assert_argv("''\"\"", { "" })
    end,
  },
  {
    name = "sandbox tokenizer treats shell metacharacters and arbitrary bytes as opaque",
    run = function()
      local opaque = "$*?|><;&#()`"
      assert_argv("run " .. opaque, { "run", opaque })
      assert_argv("run " .. string.char(0, 128, 255) .. "\195", {
        "run",
        string.char(0, 128, 255) .. "\195",
      })
    end,
  },
  {
    name = "sandbox tokenizer reports stable quote and escape failures without argv",
    run = function()
      assert_error("'unterminated", "unterminated_single_quote", "single_quoted", 13)
      assert_error('"unterminated', "unterminated_double_quote", "double_quoted", 13)
      assert_error("trailing\\", "trailing_escape", "unquoted", 8)
      assert_error('"trailing\\', "trailing_escape", "double_quoted", 9)
    end,
  },
  {
    name = "sandbox tokenizer enforces input argument count and argument byte limits at boundaries",
    run = function()
      assert_argv("abc", { "abc" }, { max_input_bytes = 3, max_argument_bytes = 3 })
      assert_error("abcd", "input_too_large", "unquoted", 3, { max_input_bytes = 3 })
      assert_argv("a b", { "a", "b" }, { max_arguments = 2 })
      assert_error("a b c", "too_many_arguments", "unquoted", 4, { max_arguments = 2 })
      assert_argv('"" a', { "", "a" }, { max_argument_bytes = 1 })
      assert_error("ab", "argument_too_large", "unquoted", 1, { max_argument_bytes = 1 })
      assert_argv("", {}, { max_input_bytes = 0, max_argument_bytes = 0 })
      assert_argv('""', { "" }, { max_argument_bytes = 0 })
      assert_error("a", "argument_too_large", "unquoted", 0, { max_argument_bytes = 0 })
    end,
  },
}
