local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\]") or ""
local root = scriptDir:gsub("[/\\]?tools[/\\]?$", "")
if root == "" then
  root = "."
end

package.path = root .. "/?.lua;" .. package.path

local state = 1

local function setRandomSeed(seed)
  state = math.floor(tonumber(seed) or 1) % 2147483647
  if state <= 0 then
    state = state + 2147483646
  end
end

local function nextRandom()
  state = (state * 48271) % 2147483647
  return state / 2147483647
end

love = love or {}
love.math = love.math or {}
love.math.setRandomSeed = love.math.setRandomSeed or setRandomSeed
love.math.random = love.math.random or function(low, high)
  local value = nextRandom()

  if low == nil then
    return value
  end

  if high == nil then
    return math.floor(value * low) + 1
  end

  return math.floor(value * (high - low + 1)) + low
end

local Level = require("level")
local count = tonumber(arg[1]) or 100
local startSeed = tonumber(arg[2]) or 1
local failed = 0

for i = 0, count - 1 do
  local seed = startSeed + i
  love.math.setRandomSeed(seed)

  local level = Level.generate(Level.width, Level.height)
  local validation = Level.validate(level)

  if not validation.valid then
    failed = failed + 1
    io.write(string.format(
      "fail seed=%d failures=%s reachable=%d/%d objectives=%d/%d gates=%d/%d usable=%d/%d\n",
      seed,
      table.concat(validation.failures, ","),
      validation.reachable,
      validation.openCells,
      validation.objectiveReachable,
      validation.objectives,
      validation.gateReachable,
      validation.gates,
      validation.gateUsable,
      validation.gates
    ))
  end
end

if failed > 0 then
  io.write(string.format("failed %d/%d seeds from %d\n", failed, count, startSeed))
  os.exit(1)
end

io.write(string.format("ok %d seeds from %d\n", count, startSeed))
