package.path = table.concat({
  "./src/?.lua",
  "./src/?/init.lua",
  "./tests/?.lua",
  "./tests/?/init.lua",
  package.path,
}, ";")

local ContinuousOutput = require("fixtures.renderer.continuous_output")
local Font = require("fixtures.renderer.font")
local Renderer = require("renderer.renderer")

local function positive_integer(value, name)
  local number = tonumber(value)
  if not number or number % 1 ~= 0 or number < 1 then
    io.stderr:write(name .. " must be a positive integer\n")
    os.exit(2)
  end
  return number
end

local frames = positive_integer(arg[1] or "1000", "frames")
local graphics = {}

function graphics.newFont()
  return Font.new()
end

function graphics.line() end

function graphics.print() end

function graphics.rectangle() end

function graphics.setColor() end

function graphics.setFont() end

local fixture = ContinuousOutput.new()
local renderer = assert(Renderer.new({}))
assert(renderer:load_font(graphics))
local snapshot = assert(fixture:advance())
assert(renderer:draw(snapshot))
collectgarbage("collect")
collectgarbage("stop")
local start_kib = collectgarbage("count")
local start_seconds = os.clock()
for _ = 1, frames do
  local next_snapshot, damage = fixture:advance()
  assert(renderer:draw(next_snapshot, damage))
end
local elapsed_seconds = os.clock() - start_seconds
local end_kib = collectgarbage("count")
collectgarbage("restart")
collectgarbage("collect")

local heap_growth_bytes = math.max(0, (end_kib - start_kib) * 1024)
local frames_per_second = elapsed_seconds > 0 and frames / elapsed_seconds or 0
print("renderer benchmark")
print("fixture=continuous_output")
print("grid=120x40")
print("frames=" .. frames)
print("lua=" .. jit.version)
print("platform=" .. jit.os .. "/" .. jit.arch)
print(string.format("elapsed_seconds=%.6f", elapsed_seconds))
print(string.format("frames_per_second=%.2f", frames_per_second))
print(string.format("gc_stopped_heap_growth_bytes=%.0f", heap_growth_bytes))
print(string.format("gc_stopped_heap_growth_bytes_per_frame=%.2f", heap_growth_bytes / frames))
