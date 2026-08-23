local Environment = require("kiwi.bench.environment")
local FontSystem = require("kiwi.font.system")
local Json = require("kiwi.bench.json")
local Layout = require("kiwi.text.layout")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")
local Stats = require("kiwi.bench.stats")
local TextStress = require("kiwi.bench.text_stress")
local Utf8 = require("kiwi.terminal.utf8")

local Longrun = {}
Longrun.maximum_report_bytes = 64 * 1024

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

local function row_cache_entries(layout)
  local count = 0
  for _ in pairs(layout.rows) do count = count + 1 end
  return count
end

local function line(index)
  local box = Utf8.encode(0x2500 + (index - 1) % 128)
  local cjk = Utf8.encode(index % 2 == 0 and 0x4e2d or 0x6587)
  local emoji = Utf8.encode(index % 3 == 0 and 0x1f680 or 0x1f469)
  return string.format("%05d Cafe%s %s %s %s\r\n", index, Utf8.encode(0x0301), cjk, emoji, box)
end

local function fragmented_update(parser, columns, rows, batch)
  local row = (batch - 1) % rows + 1
  local parts = {}
  for column = 1, columns, 2 do
    parts[#parts + 1] = string.format("\27[%d;%dH%c", row, column, 33 + (batch + column) % 90)
  end
  parser:feed(table.concat(parts))
  return #parts
end

local function accumulate_layout(total, layout)
  local stats = layout.stats
  total.rows_invalidated = total.rows_invalidated + stats.rows_invalidated
  total.rows_reshaped = total.rows_reshaped + stats.rows_reshaped
  total.runs_reshaped = total.runs_reshaped + stats.runs_reshaped
  total.glyphs_produced = total.glyphs_produced + stats.glyphs_produced
  total.shaping_cpu_ms = total.shaping_cpu_ms + stats.shaping_cpu_ms
  total.cache_hits = total.cache_hits + stats.cache_hits
  total.cache_misses = total.cache_misses + stats.cache_misses
end

function Longrun.run(options)
  options = options or {}
  local columns = options.columns or 80
  local rows = options.rows or 24
  local history_limit = options.history_limit or 4096
  local history_lines = options.history_lines or 8192
  local batch_lines = options.batch_lines or 64
  local atlas_entries = options.atlas_entries or 96
  local text_rounds = options.text_rounds or 400
  local lifecycle_iterations = options.lifecycle_iterations or 32
  local navigation_rounds = options.navigation_rounds or 8
  local rss_limit_kib = options.rss_limit_kib or 384 * 1024
  for name, value in pairs({ columns = columns, rows = rows, history_limit = history_limit, history_lines = history_lines, batch_lines = batch_lines, atlas_entries = atlas_entries, text_rounds = text_rounds, lifecycle_iterations = lifecycle_iterations, navigation_rounds = navigation_rounds, rss_limit_kib = rss_limit_kib }) do
    assert(type(value) == "number" and value >= 1 and value % 1 == 0, "long-run " .. name .. " must be a positive integer")
  end
  assert(history_lines >= history_limit + rows, "long-run history_lines must fill the configured history limit")

  local system = FontSystem.new({
    pixel_height = 18,
    fallback_cache_limit = 32,
    atlas = { width = 256, height = 256, max_entries = atlas_entries, max_bitmap_dimension = 128 },
  })
  local state = State.new(columns, rows, { max_cluster_codepoints = 16, scrollback_limit = history_limit })
  local layout = Layout.new(system)
  local parser = Parser.new(state)
  local batches = {}
  local phases = {
    damage_cpu_ms = {},
    fragmented_update_cpu_ms = {},
    input_parser_cpu_ms = {},
    layout_cpu_ms = {},
    resize_cpu_ms = {},
  }
  local layout_total = { cache_hits = 0, cache_misses = 0, glyphs_produced = 0, rows_invalidated = 0, rows_reshaped = 0, runs_reshaped = 0, shaping_cpu_ms = 0 }
  local fragmented_cells = 0
  local dirty_ranges = 0
  local resize_count = 0
  local written = 0
  collectgarbage("collect")
  local heap_before = collectgarbage("count")
  local rss_before = resident_kib()
  local peak_heap = heap_before
  local started = os.clock()

  while written < history_lines do
    local batch_started = os.clock()
    local batch = #batches + 1
    local phase_started = os.clock()
    for _ = 1, math.min(batch_lines, history_lines - written) do
      written = written + 1
      parser:feed(line(written))
    end
    phases.input_parser_cpu_ms[#phases.input_parser_cpu_ms + 1] = (os.clock() - phase_started) * 1000
    phase_started = os.clock()
    fragmented_cells = fragmented_cells + fragmented_update(parser, state.columns, state.rows, batch)
    parser:feed(string.format("\27[%d;1H", state.rows))
    phases.fragmented_update_cpu_ms[#phases.fragmented_update_cpu_ms + 1] = (os.clock() - phase_started) * 1000
    phase_started = os.clock()
    if batch % 5 == 0 then
      state:resize(columns - 1, rows)
      layout:invalidate_all()
      resize_count = resize_count + 1
    elseif batch % 5 == 1 and state.columns ~= columns then
      state:resize(columns, rows)
      layout:invalidate_all()
      resize_count = resize_count + 1
    end
    phases.resize_cpu_ms[#phases.resize_cpu_ms + 1] = (os.clock() - phase_started) * 1000
    phase_started = os.clock()
    layout:update(state)
    phases.layout_cpu_ms[#phases.layout_cpu_ms + 1] = (os.clock() - phase_started) * 1000
    accumulate_layout(layout_total, layout)
    phase_started = os.clock()
    dirty_ranges = dirty_ranges + #state.damage:ranges()
    state.damage:clear()
    phases.damage_cpu_ms[#phases.damage_cpu_ms + 1] = (os.clock() - phase_started) * 1000
    batches[#batches + 1] = (os.clock() - batch_started) * 1000
    peak_heap = math.max(peak_heap, collectgarbage("count"))
  end
  parser:finish()
  assert(state.scrollback:size() == history_limit, "long-run history did not reach its configured capacity")

  if state.columns ~= columns - 1 then
    state:resize(columns - 1, rows)
    layout:invalidate_all()
    resize_count = resize_count + 1
  end
  local navigation = {}
  local navigation_phases = { layout_cpu_ms = {}, scroll_cpu_ms = {} }
  for _ = 1, navigation_rounds do
    for _, lines in ipairs({ state.scrollback:size(), -state.scrollback:size() }) do
      local navigation_started = os.clock()
      local phase_started = os.clock()
      state:scroll_history(lines)
      navigation_phases.scroll_cpu_ms[#navigation_phases.scroll_cpu_ms + 1] = (os.clock() - phase_started) * 1000
      phase_started = os.clock()
      layout:update(state)
      navigation_phases.layout_cpu_ms[#navigation_phases.layout_cpu_ms + 1] = (os.clock() - phase_started) * 1000
      accumulate_layout(layout_total, layout)
      navigation[#navigation + 1] = (os.clock() - navigation_started) * 1000
    end
  end
  peak_heap = math.max(peak_heap, collectgarbage("count"))
  collectgarbage("collect")
  local heap_after = collectgarbage("count")
  local rss_after = resident_kib()
  local history_result = {
    batch_cpu_ms = Stats.summary(batches),
    batches = #batches,
    dirty_ranges = dirty_ranges,
    fragmented_cells = fragmented_cells,
    history_navigation_cpu_ms = Stats.summary(navigation),
    lines_written = written,
    layout = layout_total,
    phases = {
      damage_cpu_ms = Stats.summary(phases.damage_cpu_ms),
      fragmented_update_cpu_ms = Stats.summary(phases.fragmented_update_cpu_ms),
      input_parser_cpu_ms = Stats.summary(phases.input_parser_cpu_ms),
      layout_cpu_ms = Stats.summary(phases.layout_cpu_ms),
      resize_cpu_ms = Stats.summary(phases.resize_cpu_ms),
    },
    memory = {
      peak_heap_kib_delta = peak_heap - heap_before,
      retained_heap_kib_delta = heap_after - heap_before,
      rss_kib_delta = rss_before and rss_after and rss_after - rss_before or nil,
    },
    resize_count = resize_count,
    navigation_rounds = navigation_rounds,
    scrollback_limit = history_limit,
    scrollback_lines = state.scrollback:size(),
    shape_cache_rows = row_cache_entries(layout),
    navigation_phases = {
      layout_cpu_ms = Stats.summary(navigation_phases.layout_cpu_ms),
      scroll_cpu_ms = Stats.summary(navigation_phases.scroll_cpu_ms),
    },
  }
  assert(system.glyph_cache.atlas:glyph_count() <= atlas_entries, "long-run atlas entry limit exceeded")
  assert(system.fallback_cache_count <= system.fallback_cache_limit, "long-run fallback cache limit exceeded")
  if history_result.memory.rss_kib_delta then
    assert(history_result.memory.rss_kib_delta <= rss_limit_kib, string.format("long-run RSS grew %.1f KiB above %d KiB limit", history_result.memory.rss_kib_delta, rss_limit_kib))
  end
  system:destroy()

  local text_cache_pressure = TextStress.run({
    rounds = text_rounds,
    atlas_entries = atlas_entries,
    lifecycle_iterations = lifecycle_iterations,
    rss_limit_kib = rss_limit_kib,
  })
  return {
    configuration = {
      atlas_entries = atlas_entries,
      batch_lines = batch_lines,
      columns = columns,
      history_limit = history_limit,
      history_lines = history_lines,
      lifecycle_iterations = lifecycle_iterations,
      navigation_rounds = navigation_rounds,
      rows = rows,
      rss_limit_kib = rss_limit_kib,
      text_rounds = text_rounds,
    },
    history = history_result,
    text_cache_pressure = text_cache_pressure,
    unavailable = {
      gpu_renderer = "unavailable: this deterministic profile does not create a native surface or GPU resources",
      display_pacing = "unavailable: use the separate make pacing native report",
    },
  }
end

function Longrun.main()
  local result = Longrun.run({
    atlas_entries = number_from_env("KIWI_LONGRUN_ATLAS_ENTRIES", 96),
    batch_lines = number_from_env("KIWI_LONGRUN_BATCH_LINES", 64),
    history_limit = number_from_env("KIWI_LONGRUN_HISTORY_LIMIT", 4096),
    history_lines = number_from_env("KIWI_LONGRUN_HISTORY_LINES", 8192),
    lifecycle_iterations = number_from_env("KIWI_LONGRUN_LIFECYCLES", 32),
    navigation_rounds = number_from_env("KIWI_LONGRUN_NAVIGATION_ROUNDS", 8),
    rss_limit_kib = number_from_env("KIWI_LONGRUN_MAX_RSS_KIB", 384 * 1024),
    text_rounds = number_from_env("KIWI_LONGRUN_TEXT_ROUNDS", 400),
  })
  io.stdout:write(string.format(
    "long-run history=%d/%d lines batches=%d batch-p95=%.3fms input-p95=%.3fms layout-p95=%.3fms navigation-p95=%.3fms navigation-samples=%d fragmented=%d resize=%d heap=%.1f KiB rss=%s atlas=%d/%d text-cpu=%.3fms\n",
    result.history.scrollback_lines, result.history.scrollback_limit, result.history.batches,
    result.history.batch_cpu_ms.p95, result.history.phases.input_parser_cpu_ms.p95, result.history.phases.layout_cpu_ms.p95, result.history.history_navigation_cpu_ms.p95, result.history.history_navigation_cpu_ms.count,
    result.history.fragmented_cells, result.history.resize_count,
    result.history.memory.retained_heap_kib_delta,
    result.history.memory.rss_kib_delta and string.format("%.1f KiB", result.history.memory.rss_kib_delta) or "unavailable",
    result.text_cache_pressure.atlas_entries, result.text_cache_pressure.atlas_entries_limit,
    result.text_cache_pressure.elapsed_cpu_ms
  ))
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local output = "bench/results/" .. timestamp .. "-longrun.json"
  local report = {
    schema_version = 2,
    benchmark = "Kiwi M9 long-running terminal and text-cache profile",
    metadata = Environment.collect(timestamp, result.history.batches, 0),
    result = result,
  }
  local encoded = Json.encode(report)
  assert(#encoded + 1 <= Longrun.maximum_report_bytes, "long-run report exceeds 65536 bytes")
  local file, message = io.open(output, "wb")
  if not file then error("Unable to create " .. output .. ": " .. message .. ". Run through make bench-longrun so the results directory exists.") end
  file:write(encoded, "\n")
  file:close()
  io.stdout:write("machine-readable result: ", output, "\n")
end

if ... == nil then Longrun.main() end

return Longrun
