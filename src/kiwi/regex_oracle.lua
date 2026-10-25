local Regex = require("kiwi.input.regex")
local bit = require("bit")
assert(#arg == 1, "regex oracle needs its compiled POSIX helper")
local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local seed = 0x4b495749
local function random(maximum)
  seed = bit.bxor(seed, bit.lshift(seed, 13))
  seed = bit.bxor(seed, bit.rshift(seed, 17))
  seed = bit.bxor(seed, bit.lshift(seed, 5))
  return (seed < 0 and seed + 4294967296 or seed) % maximum + 1
end
local atoms = { "a", "b", "c", ".", "[ab]", "[^c]", "[a-c]" }
local quantifiers = { "", "?", "*", "+", "{0,2}", "{1,3}" }
local function pattern(depth)
  if depth == 0 or random(3) == 1 then return atoms[random(#atoms)] .. quantifiers[random(#quantifiers)] end
  if random(2) == 1 then return "(" .. pattern(depth - 1) .. "|" .. pattern(depth - 1) .. ")" .. quantifiers[random(#quantifiers)] end
  return pattern(depth - 1) .. pattern(depth - 1)
end
local cases, maximum_steps, total_steps = {}, 0, 0
-- glibc's POSIX matcher stalls on deeply nested repetition, even for ten
-- input characters; musl also disagrees with Darwin and explicit endpoint
-- checks on some nested bounded repeats. Linux uses shallow generated cases.
-- Both platforms retain the same separate adversarial NFA work/heap gates.
local maximum_depth = require("jit").os == "Linux" and 1 or 3
for _ = 1, 5000 do
  local text = {}
  for _ = 1, random(60) - 1 do local index = random(4); text[#text + 1] = string.sub("abcz", index, index) end
  local expression = pattern(maximum_depth)
  if random(4) == 1 then expression = "^" .. expression end
  if random(4) == 1 then expression = expression .. "$" end
  cases[#cases + 1] = { pattern = expression, text = table.concat(text) }
end
local path = os.tmpname()
local pipe
local started = os.clock()
local ok, message = xpcall(function()
  local file = assert(io.open(path, "wb"))
  for _, case in ipairs(cases) do file:write(case.pattern, "\t", case.text, "\n") end
  assert(file:close())
  pipe = assert(io.popen(quote(arg[1]) .. " " .. quote(path), "r"))
  for index, case in ipairs(cases) do
    local expected = assert(pipe:read("*l"), string.format("POSIX oracle exited before case %d: /%s/ on %q", index, case.pattern, case.text))
    local program, reason = Regex.compile(case.pattern)
    assert(program, reason)
    local runner = Regex.runner(program, Regex.scalars(case.text))
    while not runner.done do
      runner:step(4096)
      assert(runner.steps < 2000000, "generated regex exceeded its work bound")
    end
    local observed = runner.first and (runner.first .. " " .. runner.last) or "none"
    assert(observed == expected, string.format("POSIX mismatch case %d: /%s/ on %q expected %s, got %s", index, case.pattern, case.text, expected, observed))
    maximum_steps = math.max(maximum_steps, runner.steps)
    total_steps = total_steps + runner.steps
  end
  assert(pipe:read("*l") == nil, "POSIX oracle emitted extra output")
  assert(pipe:close()); pipe = nil
end, debug.traceback)
if pipe then pipe:close() end
os.remove(path)
assert(ok, message)
print(string.format("Regex POSIX oracle passed: %d seeded cases (depth %d), %d total transitions, %d maximum, %.3f Lua CPU seconds.", #cases, maximum_depth, total_steps, maximum_steps, os.clock() - started))
