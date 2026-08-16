local Assert = require("tests.assert")
local Fuzz = require("kiwi.terminal.fuzz")

return {
  parser_fuzz_minimizes_a_reproducible_input = function()
    local reduced = Fuzz.minimize("abcXdef", function(input) return input:find("X", 1, true) ~= nil end)
    Assert.equal(reduced, "X")
  end,
  parser_fuzz_runs_saved_corpus_and_seeded_cases = function()
    local result = Fuzz.run({ seed = 17, cases = 3, maximum_bytes = 48 })
    Assert.equal(result.corpus, 6)
    Assert.equal(result.cases, 3)
    Assert.equal(result.seed, 17)
    Assert.equal(result.maximum_bytes, 48)
    Assert.equal(Fuzz.decode_hexadecimal("1b5b33316d"), "\27[31m")
  end,
}
