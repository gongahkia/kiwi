local Assert = require("tests.assert")
local Regex = require("kiwi.input.regex")
local function find(pattern, text, budget, literal)
  local program, reason = Regex.compile(pattern, literal)
  assert(program, reason)
  local runner = Regex.runner(program, Regex.scalars(text))
  local ticks = 0
  repeat
    local done, first, last, used = runner:step(budget or 64)
    Assert.truthy(used <= (budget or 64))
    ticks = ticks + 1
    assert(ticks < 100000, "regex runner failed to finish")
    if done then return first, last, runner.steps end
  until false
end
return {
  regex_matches_leftmost_longest_and_bounded_repetition = function()
    local cases = {
      { "ab|abc", "xabcab", 2, 4 }, { "(ab|a)+", "xxaba!", 3, 5 },
      { "a{2,4}", "zaaaaa", 2, 5 }, { "a{2,}", "zaaaaa", 2, 6 },
      { "^ab$", "ab", 1, 2 }, { "^ab$", "zab" },
      { "a?b*", "zabbb", 1, 0 }, { "(a?)*b", "aaab", 1, 4 },
      { "a.*z|b", "abbbb", 2, 2 }, { "a.*z|a", "aaaa", 1, 1 },
      { "(?:cat|dog)s?", "dogs cats", 1, 4 }, { "a{0}", "bbb", 1, 0 },
      { "(a|)b", "b", 1, 1 }, { "$", "ab", 3, 2 },
    }
    for _, case in ipairs(cases) do
      for _, budget in ipairs({ 1, 7, 4096 }) do
        local first, last = find(case[1], case[2], budget)
        Assert.equal(first, case[3], case[1]); Assert.equal(last, case[4], case[1])
      end
    end
  end,
  regex_classes_and_boundaries_use_documented_scalar_semantics = function()
    local cases = {
      { "[a-c]+", "xxabccz", 3, 6 }, { "[^a-c]+", "abcz!", 4, 5 },
      { "[\\D0]+", "12x0!3", 3, 5 }, { "\\bcat\\b", "scatter cat!", 9, 11 },
      { "\\Bcat", "scat", 2, 4 }, { "\\d+\\s\\w+", "@12 abc!", 2, 7 },
      { "[中-文]+", "x中文z", 2, 3 }, { ".", "😀", 1, 1 },
      { "e.", "xéy", 2, 3 }, { "\\[x\\]", "[x]", 1, 3 },
      { "[-a]+", "a--z", 1, 3 }, { "[a-]+", "a--z", 1, 3 },
    }
    for _, case in ipairs(cases) do
      local first, last = find(case[1], case[2], 3)
      Assert.equal(first, case[3], case[1]); Assert.equal(last, case[4], case[1])
    end
  end,
  regex_rejects_unsupported_and_unbounded_patterns_before_execution = function()
    for _, pattern in ipairs({ "[", "[z-a]", "[]", "(", ")", "a**", "a+?", "\\1", "(?=x)", "\\p{L}",
      "a{129}", "a{3,2}", "a{", "\\", "\255", "a\0b", string.rep("a", 1025),
      string.rep("(", 33) .. "a" .. string.rep(")", 33), "(a{128}){128}" }) do
      local program, reason = Regex.compile(pattern)
      Assert.equal(program, nil, pattern); Assert.truthy(type(reason) == "string" and #reason > 0)
    end
  end,
  regex_nested_repetition_has_linear_work_and_resumable_state = function()
    local _, _, small = find("(a+)+$", string.rep("a", 100) .. "!", 19)
    local first, _, large = find("(a+)+$", string.rep("a", 1000) .. "!", 19)
    Assert.equal(first, nil)
    Assert.truthy(large < small * 11, "nested repeats grew faster than the input")
    Assert.truthy(large < 40000, "nested repeats exceeded the expected NFA work bound")
  end,
  literal_matcher_keeps_regex_punctuation_literal_and_avoids_quadratic_prefixes = function()
    local first, last = find("[a]+", "x[a]+y", 1, true)
    Assert.equal(first, 2); Assert.equal(last, 5)
    first, last = find("中文", "x中文z", 2, true)
    Assert.equal(first, 2); Assert.equal(last, 3)
    local steps
    first, last, steps = find(string.rep("a", 100) .. "b", string.rep("a", 10000) .. "b", 64, true)
    Assert.equal(first, 9901); Assert.equal(last, 10001)
    Assert.truthy(steps < 21000)
  end,
}
