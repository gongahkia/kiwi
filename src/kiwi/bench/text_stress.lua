local Environment = require("kiwi.bench.environment")
local FontSystem = require("kiwi.font.system")
local Json = require("kiwi.bench.json")
local Layout = require("kiwi.text.layout")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")
local Utf8 = require("kiwi.terminal.utf8")

local TextStress = {}

local function number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value > 0 and math.floor(value) or fallback
end

local function resident_kib()
  local file = io.open("/proc/self/status", "r")
  if not file then return nil end
  for line in file:lines() do
    local value = line:match("^VmRSS:%s+(%d+)%s+kB$")
    if value then
      file:close()
      return tonumber(value)
    end
  end
  file:close()
  return nil
end

local function write(state, codepoint)
  state:write_codepoint(Utf8.encode(codepoint), codepoint)
end

local function assert_row_invariants(state)
  for row = 0, state.rows - 1 do
    for column = 0, state.columns - 1 do
      local cell = state:get(column, row)
      if cell.continuation then
        assert(column > 0, "continuation occupies first column")
        local anchor = state:get(column - 1, row)
        assert(not anchor.continuation and anchor.width == 2 and cell.anchor_column == column - 1, "orphan continuation")
      elseif cell.width == 2 then
        assert(column + 1 < state.columns, "wide anchor occupies right margin")
        local continuation = state:get(column + 1, row)
        assert(continuation.continuation and continuation.anchor_column == column, "wide anchor lacks continuation")
      end
    end
  end
end

function TextStress.run(options)
  options = options or {}
  local rounds = options.rounds or 400
  local atlas_entries = options.atlas_entries or 96
  local rss_limit_kib = options.rss_limit_kib or 96 * 1024
  local system = FontSystem.new({
    pixel_height = 18,
    fallback_cache_limit = 32,
    atlas = { width = 256, height = 256, max_entries = atlas_entries, max_bitmap_dimension = 128 },
  })
  local state = State.new(80, 6, { max_cluster_codepoints = 16, scrollback_limit = 32 })
  local layout = Layout.new(system)
  local parser = Parser.new(state)
  local inputs = { 0x41, 0x65, 0x301, 0x4e2d, 0x6587, 0x1f469, 0x200d, 0x1f680, 0x2764, 0xfe0f, 0xe0b0, 0x10ffff }
  local started = os.clock()
  collectgarbage("collect")
  local heap_before = collectgarbage("count")
  local rss_before = resident_kib()
  local peak_heap = heap_before
  local initial_failures = system.glyph_cache.stats.failures
  for round = 1, rounds do
    for _, codepoint in ipairs(inputs) do write(state, codepoint) end
    if round % 5 == 0 then parser:feed("\27[2P\27[1@") end
    if round % 7 == 0 then parser:feed("\r\n") end
    if round % 11 == 0 then
      state:resize(79 + (round % 2), 6)
      layout:invalidate_all()
    end
    layout:update(state)
    assert_row_invariants(state)
    assert(system.glyph_cache.atlas:glyph_count() <= atlas_entries, "glyph atlas entry limit exceeded")
    assert(system.fallback_cache_count <= system.fallback_cache_limit, "fallback cache limit exceeded")
    peak_heap = math.max(peak_heap, collectgarbage("count"))
    state.damage:clear()
  end
  parser:finish()
  collectgarbage("collect")
  local heap_after = collectgarbage("count")
  local rss_after = resident_kib()
  local result = {
    rounds = rounds,
    atlas_entries_limit = atlas_entries,
    atlas_entries = system.glyph_cache.atlas:glyph_count(),
    atlas_occupancy = system.glyph_cache.atlas:occupancy(),
    glyph_cache = system.glyph_cache.stats,
    fallback = system.stats,
    width_change_clamped = state.stats.text.width_change_clamped,
    over_limit_clusters = state.stats.text.over_limit_clusters,
    elapsed_cpu_ms = (os.clock() - started) * 1000,
    memory = {
      peak_heap_kib_delta = peak_heap - heap_before,
      retained_heap_kib_delta = heap_after - heap_before,
      rss_kib_delta = rss_before and rss_after and rss_after - rss_before or nil,
    },
  }
  assert(result.glyph_cache.failures >= initial_failures, "glyph failure counter regressed")
  if result.memory.rss_kib_delta then
    assert(result.memory.rss_kib_delta <= rss_limit_kib, string.format("RSS grew %.1f KiB above %d KiB limit", result.memory.rss_kib_delta, rss_limit_kib))
  end
  system:destroy()
  return result
end

function TextStress.main()
  local result = TextStress.run({
    rounds = number_from_env("KIWI_TEXT_STRESS_ROUNDS", 400),
    atlas_entries = number_from_env("KIWI_TEXT_STRESS_ATLAS_ENTRIES", 96),
    rss_limit_kib = number_from_env("KIWI_TEXT_STRESS_MAX_RSS_KIB", 96 * 1024),
  })
  io.stdout:write(string.format(
    "text-stress rounds=%d cpu=%.3fms atlas=%d/%d occupancy=%.3f failures=%d fallback=%d/%d heap=%.1f KiB rss=%s\n",
    result.rounds, result.elapsed_cpu_ms, result.atlas_entries, result.atlas_entries_limit, result.atlas_occupancy, result.glyph_cache.failures,
    result.fallback.fallback_hits, result.fallback.fallback_misses, result.memory.retained_heap_kib_delta,
    result.memory.rss_kib_delta and string.format("%.1f KiB", result.memory.rss_kib_delta) or "unavailable"
  ))
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local output = "bench/results/" .. timestamp .. "-text-stress.json"
  local file, message = io.open(output, "wb")
  if not file then error("Unable to create " .. output .. ": " .. message .. ". Run through make bench-text-stress so the results directory exists.") end
  file:write(Json.encode({
    schema_version = 1,
    benchmark = "Kiwi M2 bounded native text stress",
    metadata = Environment.collect(timestamp, result.rounds, 0),
    result = result,
  }), "\n")
  file:close()
  io.stdout:write("machine-readable result: " .. output .. "\n")
end

if ... == nil then TextStress.main() end

return TextStress
