local Fuzz = require("kiwi.terminal.fuzz")

local function number_from_env(name, fallback, minimum)
  local value = os.getenv(name)
  if value == nil or #value == 0 then return fallback end
  local number = tonumber(value)
  assert(number and number >= minimum and number % 1 == 0, name .. " must be an integer no less than " .. minimum)
  return number
end

local seed = number_from_env("KIWI_FUZZ_SEED", 0x4b495749, 1)
local cases = number_from_env("KIWI_FUZZ_CASES", 128, 0)
local maximum_bytes = number_from_env("KIWI_FUZZ_MAX_BYTES", 512, 1)
local replay = os.getenv("KIWI_FUZZ_REPLAY_HEX")
local result
if replay and #replay > 0 then
  result = Fuzz.run({ seed = seed, cases = 0, input = Fuzz.decode_hexadecimal(replay), include_corpus = false })
else
  result = Fuzz.run({ seed = seed, cases = cases, maximum_bytes = maximum_bytes })
end
io.stdout:write(string.format("parser fuzz passed corpus=%d cases=%d seed=%d maximum-bytes=%d\n", result.corpus, result.cases, result.seed, result.maximum_bytes))
