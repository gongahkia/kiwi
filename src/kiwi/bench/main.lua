local ffi = require("ffi")
local Synthetic = require("kiwi.terminal.synthetic")
local Packing = require("kiwi.renderer.packing")
local Stats = require("kiwi.bench.stats")
local Json = require("kiwi.bench.json")

local function number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value > 0 and math.floor(value) or fallback
end

local function pack_range(model, instances, first, count)
  for index = first, first + count - 1 do
    local column, row = model:position(index)
    local cell = model.cells[index]
    local instance = instances[index]
    instance.x = column
    instance.y = row
    instance.u0 = 0
    instance.v0 = 0
    instance.u1 = 1
    instance.v1 = 1
    instance.fg = ffi.cast("uint32_t", cell.fg)
    instance.bg = ffi.cast("uint32_t", cell.bg)
    instance.flags = cell.flags
    instance.glyph = string.byte(cell.glyph) or 0
  end
end

local function run_scenario(columns, rows, scenario, iterations)
  local model = Synthetic.new(0x4b495749, columns, rows)
  local instances = ffi.new("KiwiGlyphInstance[?]", columns * rows)
  local samples = {}
  local changed_total = 0
  local uploaded_total = 0
  local bytes_total = 0
  local ranges_total = 0
  local full_updates = 0

  for iteration = 1, iterations do
    local started = os.clock()
    Synthetic.apply(model, scenario, iteration)
    local damage = model.damage
    local ranges = damage:ranges()
    for _, range in ipairs(ranges) do
      pack_range(model, instances, range.first, range.count)
      uploaded_total = uploaded_total + range.count
      bytes_total = bytes_total + Packing.bytes_for_cells(range.count)
    end
    samples[#samples + 1] = (os.clock() - started) * 1000
    changed_total = changed_total + damage.dirty_count
    ranges_total = ranges_total + #ranges
    if damage.full then
      full_updates = full_updates + 1
    end
    damage:clear()
  end

  local latency = Stats.summary(samples)
  return {
    scenario = scenario,
    columns = columns,
    rows = rows,
    iterations = iterations,
    cells_changed = changed_total,
    cells_uploaded = uploaded_total,
    bytes_uploaded = bytes_total,
    dirty_ranges = ranges_total,
    full_updates = full_updates,
    draw_calls_per_frame = 3,
    cpu_update_ms = latency,
  }
end

local function print_result(result)
  io.stdout:write(string.format(
    "%s %dx%d iterations=%d cpu_update mean=%.4fms p50=%.4fms p95=%.4fms p99=%.4fms changed=%d uploaded=%d bytes=%d ranges=%d full=%d draws/frame=%d\n",
    result.scenario,
    result.columns,
    result.rows,
    result.iterations,
    result.cpu_update_ms.mean,
    result.cpu_update_ms.p50,
    result.cpu_update_ms.p95,
    result.cpu_update_ms.p99,
    result.cells_changed,
    result.cells_uploaded,
    result.bytes_uploaded,
    result.dirty_ranges,
    result.full_updates,
    result.draw_calls_per_frame
  ))
end

local iterations = number_from_env("KIWI_BENCH_ITERATIONS", 300)
local results = {}
for _, dimensions in ipairs({ { 160, 50 }, { 240, 80 } }) do
  for _, scenario in ipairs(Synthetic.scenarios()) do
    local result = run_scenario(dimensions[1], dimensions[2], scenario, iterations)
    results[#results + 1] = result
    print_result(result)
  end
end

local timestamp = os.date("!%Y%m%dT%H%M%SZ")
local output = "bench/results/" .. timestamp .. ".json"
local file, error_message = io.open(output, "wb")
if not file then
  error("Unable to create " .. output .. ": " .. error_message .. ". Run through make bench so the results directory exists.")
end
file:write(Json.encode({
  schema_version = 1,
  timestamp_utc = timestamp,
  engine = "LuaJIT terminal-model/damage/packing benchmark",
  gpu_timing = "unsupported (headless benchmark does not request timestamp-query feature)",
  results = results,
}), "\n")
file:close()
io.stdout:write("machine-readable result: " .. output .. "\n")
