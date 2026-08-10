local ffi = require("ffi")
local Environment = require("kiwi.bench.environment")
local FontSystem = require("kiwi.font.system")
local Json = require("kiwi.bench.json")
local Layout = require("kiwi.text.layout")
local Parser = require("kiwi.terminal.parser")
local Renderer = require("kiwi.renderer.renderer")
local State = require("kiwi.terminal.state")
local Stats = require("kiwi.bench.stats")
local Utf8 = require("kiwi.terminal.utf8")

local WriteBench = {}

local function number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value > 0 and math.floor(value) or fallback
end

local function measure(iterations, warmup, setup, operation, inspect, cleanup)
  for _ = 1, warmup do
    local context = setup()
    operation(context)
    if inspect then inspect(context, false) end
    if cleanup then cleanup(context) end
  end
  collectgarbage("collect")
  local heap_before = collectgarbage("count")
  local heap_peak = heap_before
  local samples = {}
  for iteration = 1, iterations do
    local context = setup()
    local started = os.clock()
    operation(context)
    samples[iteration] = (os.clock() - started) * 1000
    if inspect then inspect(context, true) end
    heap_peak = math.max(heap_peak, collectgarbage("count"))
    if cleanup then cleanup(context) end
  end
  collectgarbage("collect")
  return Stats.summary(samples), {
    peak_kib_delta = heap_peak - heap_before,
    retained_kib_delta = collectgarbage("count") - heap_before,
  }
end

local function result(stage, workload, input, iterations, warmup, timing, memory, counters, scope)
  local seconds = timing.total / 1000
  return {
    stage = stage,
    workload = workload,
    scope = scope,
    input_bytes_per_iteration = #input,
    iterations = iterations,
    warmup_iterations = warmup,
    throughput_bytes_per_second = seconds > 0 and #input * iterations / seconds or 0,
    cpu_ms = timing,
    memory = memory,
    counters = counters,
  }
end

local function add_counter(target, source, name)
  target[name] = (target[name] or 0) + (source[name] or 0)
end

local function state_counters(state, parser)
  local counters = state.text_counters or {}
  return {
    input_bytes = parser and parser.stats.bytes or 0,
    parser_actions = parser and parser.stats.actions or 0,
    parser_errors = parser and parser.stats.errors or 0,
    unicode_scalars = counters.unicode_scalars or 0,
    ascii_fast_path = counters.ascii_fast_path or 0,
    unicode_property_lookups = counters.unicode_property_lookups or 0,
    grapheme_boundary_checks = counters.grapheme_boundary_checks or 0,
    width_policy_calls = counters.width_policy_calls or 0,
    clusters_created = counters.clusters_created or 0,
    clusters_extended = counters.clusters_extended or 0,
    cells_changed = counters.cells_changed or 0,
    logical_dirty_cells = state.damage.dirty_count,
    logical_dirty_ranges = #state.damage:ranges(),
    text_dirty_cells = state.text_damage.dirty_count,
    text_dirty_ranges = #state.text_damage:ranges(),
  }
end

local function layout_counters(layout, system)
  local stats = layout.stats
  return {
    rows_invalidated = stats.rows_invalidated or 0,
    rows_reshaped = stats.rows_reshaped or 0,
    runs_built = stats.runs_built or 0,
    runs_reshaped = stats.runs_reshaped or 0,
    clusters_examined = stats.clusters_examined or 0,
    codepoints_shaped = stats.codepoints_shaped or 0,
    glyphs_produced = stats.glyphs_produced or 0,
    glyph_cache_hits = system.glyph_cache.stats.hits,
    glyph_cache_misses = system.glyph_cache.stats.misses,
    fallback_primary_hits = system.stats.primary_hits,
    primary_ascii_cache_hits = system.stats.primary_ascii_cache_hits,
    primary_ascii_coverage_probes = system.stats.primary_ascii_coverage_probes,
    fallback_hits = system.stats.fallback_hits,
    fallback_misses = system.stats.fallback_misses,
  }
end

local function merge_counters(target, source)
  for name, value in pairs(source) do target[name] = (target[name] or 0) + value end
end

local function new_state()
  local state = State.new(80, 24, { scrollback_limit = 256, text_counters = {} })
  state.damage:clear()
  state.text_damage:clear()
  return state
end

local function feed(state, input)
  local parser = Parser.new(state)
  parser:feed(input)
  parser:finish()
  return parser
end

local function decode_stage(item, iterations, warmup)
  local counters = { unicode_scalars = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { scalars = 0, decoder = nil }
  end, function(context)
    context.decoder = Utf8.Decoder.new(function() context.scalars = context.scalars + 1 end)
    for index = 1, #item.input do context.decoder:feed_byte(item.input:byte(index)) end
    context.decoder:finish()
  end, function(context, recorded)
    if recorded then counters.unicode_scalars = counters.unicode_scalars + context.scalars end
  end)
  return result("utf8-decode", item.name, item.input, iterations, warmup, timing, memory, counters,
    "Byte iteration and UTF-8 decoder callbacks only; parser, terminal state, shaping, rasterization, GPU submission, and presentation are excluded")
end

local function parser_state_stage(item, iterations, warmup)
  local counters = {}
  local timing, memory = measure(iterations, warmup, function()
    local state = new_state()
    return { state = state, parser = Parser.new(state) }
  end, function(context)
    context.parser:feed(item.input)
    context.parser:finish()
  end, function(context, recorded)
    if recorded then merge_counters(counters, state_counters(context.state, context.parser)) end
  end)
  return result("parser-cluster-mutation-logical-damage", item.name, item.input, iterations, warmup, timing, memory, counters,
    "Production parser direct-print sink, UTF-8 decoding, UAX #29 terminal cluster mutation, width policy, and logical/text damage; shaping, rasterization, GPU submission, and presentation are excluded")
end

local function with_populated_layout(item)
  local state = new_state()
  local parser = feed(state, item.input)
  local system = FontSystem.new({ pixel_height = 18, atlas = { width = 512, height = 512, max_entries = 1024 } })
  local layout = Layout.new(system)
  layout:begin_frame()
  return { state = state, parser = parser, system = system, layout = layout }
end

local function run_build_stage(item, iterations, warmup)
  local counters = {}
  local timing, memory = measure(iterations, warmup, function()
    return with_populated_layout(item)
  end, function(context)
    context.runs = {}
    for row = 0, context.state.rows - 1 do
      local runs = context.layout:build_runs(context.state, row)
      for _, run in ipairs(runs) do context.runs[#context.runs + 1] = run end
    end
  end, function(context, recorded)
    if recorded then
      merge_counters(counters, state_counters(context.state, context.parser))
      merge_counters(counters, layout_counters(context.layout, context.system))
    end
  end, function(context)
    context.system:destroy()
  end)
  return result("row-run-construction-fallback", item.name, item.input, iterations, warmup, timing, memory, counters,
    "Visible terminal rows through cluster inspection, primary coverage checks, Fontconfig fallback decisions, and contiguous same-face run construction; HarfBuzz shaping, glyph rasterization, GPU submission, and presentation are excluded")
end

local function harfbuzz_stage(item, iterations, warmup, glyph_records)
  local counters = {}
  local timing, memory = measure(iterations, warmup, function()
    local context = with_populated_layout(item)
    context.runs = {}
    for row = 0, context.state.rows - 1 do
      local runs = context.layout:build_runs(context.state, row)
      context.runs[row] = runs
    end
    context.layout:begin_frame()
    return context
  end, function(context)
    context.glyphs = {}
    for row = 0, context.state.rows - 1 do
      local glyphs = context.layout:shape_runs(context.runs[row], row)
      if glyph_records then
        for _, glyph in ipairs(glyphs) do context.glyphs[#context.glyphs + 1] = glyph end
      end
    end
  end, function(context, recorded)
    if recorded then
      merge_counters(counters, state_counters(context.state, context.parser))
      merge_counters(counters, layout_counters(context.layout, context.system))
      counters.glyph_records = (counters.glyph_records or 0) + #context.glyphs
    end
  end, function(context)
    context.system:destroy()
  end)
  local stage = glyph_records and "harfbuzz-atlas-glyph-records" or "harfbuzz-shaping"
  local scope = glyph_records
    and "Prebuilt row runs through HarfBuzz shaping, FreeType glyph-cache miss/rasterization, atlas insertion, and Lua glyph-record generation; GPU atlas upload, GPU submission, and presentation are excluded"
    or "Prebuilt row runs through HarfBuzz shaping only; fallback resolution, glyph cache/rasterization, atlas insertion, GPU submission, and presentation are excluded"
  return result(stage, item.name, item.input, iterations, warmup, timing, memory, counters, scope)
end

local function invalidation_stage(item, iterations, warmup)
  local counters = {}
  local timing, memory = measure(iterations, warmup, function()
    local context = with_populated_layout(item)
    context.layout:update(context.state)
    context.state.damage:clear()
    return context
  end, function(context)
    context.state:move_relative(0, 1)
    context.glyphs = context.layout:update(context.state)
  end, function(context, recorded)
    if recorded then
      merge_counters(counters, layout_counters(context.layout, context.system))
      counters.logical_dirty_cells = (counters.logical_dirty_cells or 0) + context.state.damage.dirty_count
      counters.text_dirty_cells = (counters.text_dirty_cells or 0) + context.state.text_damage.dirty_count
      counters.glyph_records = (counters.glyph_records or 0) + #context.glyphs
    end
  end, function(context)
    context.system:destroy()
  end)
  return result("shape-invalidation-cursor-only", item.name, item.input, iterations, warmup, timing, memory, counters,
    "A cached static layout after cursor-only logical damage; row shaping, fallback, glyph cache mutation, atlas work, GPU submission, and presentation are excluded")
end

local function full_stage(item, iterations, warmup)
  local counters = {}
  local timing, memory = measure(iterations, warmup, function()
    local state = new_state()
    local system = FontSystem.new({ pixel_height = 18, atlas = { width = 512, height = 512, max_entries = 1024 } })
    return { state = state, parser = Parser.new(state), system = system, layout = Layout.new(system) }
  end, function(context)
    context.parser:feed(item.input)
    context.parser:finish()
    context.glyphs = context.layout:update(context.state)
  end, function(context, recorded)
    if recorded then
      merge_counters(counters, state_counters(context.state, context.parser))
      merge_counters(counters, layout_counters(context.layout, context.system))
      counters.glyph_records = (counters.glyph_records or 0) + #context.glyphs
    end
  end, function(context)
    context.system:destroy()
  end)
  return result("full-parser-to-glyph-record", item.name, item.input, iterations, warmup, timing, memory, counters,
    "In-memory terminal bytes through production parser, UTF-8, terminal grapheme/width mutation, logical and text damage, invalidated-row run construction, fallback, HarfBuzz, glyph cache/atlas, and Lua glyph records; PTY syscalls, GPU atlas upload, GPU submission, execution, and presentation are excluded")
end

local function glyph_record_packing_stage(item, iterations, warmup)
  local counters = {}
  local timing, memory = measure(iterations, warmup, function()
    local context = with_populated_layout(item)
    context.glyphs = context.layout:update(context.state)
    context.packer = { glyphs = ffi.new("KiwiTextGlyphInstance[?]", math.max(1, #context.glyphs)) }
    return context
  end, function(context)
    for index, glyph in ipairs(context.glyphs) do Renderer.pack_shaped_glyph(context.packer, glyph, index - 1) end
  end, function(context, recorded)
    if recorded then
      merge_counters(counters, state_counters(context.state, context.parser))
      counters.glyph_records_packed = (counters.glyph_records_packed or 0) + #context.glyphs
    end
  end, function(context)
    context.system:destroy()
  end)
  return result("renderer-glyph-record-packing", item.name, item.input, iterations, warmup, timing, memory, counters,
    "Prebuilt shaped glyphs through Renderer:pack_shaped_glyph into the real 48-byte FFI record layout; shaping, rasterization, atlas lookup, GPU queue writes, execution, and presentation are excluded")
end

local function make_workloads()
  local emoji = Utf8.encode(0x1f469) .. Utf8.encode(0x200d) .. Utf8.encode(0x1f680)
  local unicode = "Cafe" .. Utf8.encode(0x0301) .. " " .. Utf8.encode(0x4e2d) .. " " .. emoji .. " " .. Utf8.encode(0xe0b0) .. "\n"
  return {
    { name = "ascii-full-dirty-row", input = string.rep("Kiwi terminal write path 0123456789 ", 24) },
    { name = "unicode-combining-cjk-emoji-fallback", input = string.rep(unicode, 32) },
  }
end

local function ascii_mutation_control(item, iterations, warmup)
  local repetitions_per_sample = 16
  local control_input = string.rep(item.input, repetitions_per_sample)
  local direct = State.set_ascii_cell
  local function legacy(self, column, row, glyph, codepoints)
    return self:set_cell(column, row, self:ascii_cell(glyph, codepoints))
  end
  local function run_block(setter)
    State.set_ascii_cell = setter
    jit.flush()
    for _ = 1, warmup do
      for _ = 1, repetitions_per_sample do
        local state = new_state()
        local parser = Parser.new(state)
        parser:feed(item.input)
        parser:finish()
      end
    end
    collectgarbage("collect")
    local heap_before = collectgarbage("count")
    local heap_peak = heap_before
    local samples, counters = {}, {}
    for iteration = 1, iterations do
      local started = os.clock()
      for _ = 1, repetitions_per_sample do
        local state = new_state()
        local parser = Parser.new(state)
        parser:feed(item.input)
        parser:finish()
        merge_counters(counters, state_counters(state, parser))
      end
      samples[iteration] = (os.clock() - started) * 1000
      heap_peak = math.max(heap_peak, collectgarbage("count"))
    end
    collectgarbage("collect")
    return samples, counters, heap_peak - heap_before, collectgarbage("count") - heap_before
  end

  local legacy_samples, direct_samples, counters = {}, {}, {}
  local peak_kib_delta, retained_kib_delta = 0, 0
  for _, setter in ipairs({ legacy, direct, direct, legacy }) do
    local samples, block_counters, block_peak, block_retained = run_block(setter)
    local target = setter == legacy and legacy_samples or direct_samples
    for _, sample in ipairs(samples) do target[#target + 1] = sample end
    if setter == direct then merge_counters(counters, block_counters) end
    peak_kib_delta = math.max(peak_kib_delta, block_peak)
    retained_kib_delta = math.max(retained_kib_delta, block_retained)
  end
  State.set_ascii_cell = direct
  jit.flush()
  local direct_timing = Stats.summary(direct_samples)
  local legacy_timing = Stats.summary(legacy_samples)
  local control = result("ascii-cell-mutation-control", item.name, control_input, iterations * 2, warmup * 2, direct_timing, {
    peak_kib_delta = peak_kib_delta,
    retained_kib_delta = retained_kib_delta,
  }, counters,
    "Within one LuaJIT process, two legacy and two direct mutation blocks with a LuaJIT flush before each block. Each measured sample repeats the same fresh parser/state write 16 times to reduce clock quantization; blocks otherwise have identical input, state dimensions, and warm-up. The legacy path creates a transient ascii_cell before set_cell/copy_cell; shaping, GPU submission, and presentation are excluded")
  control.control = {
    legacy_cpu_ms = legacy_timing,
    direct_cpu_ms = direct_timing,
    repetitions_per_sample = repetitions_per_sample,
  }
  return control
end

function WriteBench.run(iterations, warmup)
  iterations = iterations or 25
  warmup = warmup or 5
  local results = {}
  for _, item in ipairs(make_workloads()) do
    if item.name == "ascii-full-dirty-row" then results[#results + 1] = ascii_mutation_control(item, iterations, warmup) end
    results[#results + 1] = decode_stage(item, iterations, warmup)
    results[#results + 1] = parser_state_stage(item, iterations, warmup)
    results[#results + 1] = run_build_stage(item, iterations, warmup)
    results[#results + 1] = harfbuzz_stage(item, iterations, warmup, false)
    results[#results + 1] = harfbuzz_stage(item, iterations, warmup, true)
    results[#results + 1] = glyph_record_packing_stage(item, iterations, warmup)
    results[#results + 1] = invalidation_stage(item, iterations, warmup)
    results[#results + 1] = full_stage(item, iterations, warmup)
  end
  return results
end

function WriteBench.print_results(results)
  for _, item in ipairs(results) do
    local counters = item.counters
    io.stdout:write(string.format(
      "m2.5 %-36s %-34s iterations=%d mean=%.4fms p50=%.4fms p95=%.4fms p99=%.4fms scalars=%d clusters=%d/%d runs=%d/%d glyphs=%d records=%d dirty=%d/%d cache=%d/%d fallback=%d/%d heap=%.1f/%.1f KiB\n",
      item.stage, item.workload, item.iterations, item.cpu_ms.mean, item.cpu_ms.p50, item.cpu_ms.p95, item.cpu_ms.p99,
      counters.unicode_scalars or 0, counters.clusters_created or 0, counters.clusters_extended or 0,
      counters.runs_built or 0, counters.runs_reshaped or 0, counters.glyphs_produced or 0, counters.glyph_records or 0,
      counters.logical_dirty_cells or 0, counters.text_dirty_cells or 0,
      counters.glyph_cache_hits or 0, counters.glyph_cache_misses or 0,
      counters.fallback_hits or 0, counters.fallback_misses or 0,
      item.memory.retained_kib_delta, item.memory.peak_kib_delta
    ))
    if item.control then
      io.stdout:write(string.format(
        "      control fresh-writes/sample=%d legacy p50=%.4fms p95=%.4fms p99=%.4fms direct p50=%.4fms p95=%.4fms p99=%.4fms\n",
        item.control.repetitions_per_sample,
        item.control.legacy_cpu_ms.p50, item.control.legacy_cpu_ms.p95, item.control.legacy_cpu_ms.p99,
        item.control.direct_cpu_ms.p50, item.control.direct_cpu_ms.p95, item.control.direct_cpu_ms.p99
      ))
    end
  end
end

function WriteBench.main()
  local iterations = number_from_env("KIWI_WRITE_BENCH_ITERATIONS", 25)
  local warmup = number_from_env("KIWI_WRITE_BENCH_WARMUP", 5)
  local results = WriteBench.run(iterations, warmup)
  WriteBench.print_results(results)
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local output = "bench/results/" .. timestamp .. "-write.json"
  local system = FontSystem.new({ pixel_height = 18, atlas = { width = 512, height = 512, max_entries = 1024 } })
  local configuration = {
    primary_font_path = system.font_path,
    pixel_height = system.pixel_height,
    face_cache_limit = system.face_cache_limit,
    fallback_cache_limit = system.fallback_cache_limit,
    ligatures = system.shape_options.ligatures,
    contextual_alternates = system.shape_options.contextual_alternates,
    atlas = { width = system.glyph_cache.atlas.width, height = system.glyph_cache.atlas.height, max_entries = system.glyph_cache.max_entries },
  }
  system:destroy()
  local file, message = io.open(output, "wb")
  if not file then error("Unable to create " .. output .. ": " .. message .. ". Run through make bench-write so the results directory exists.") end
  file:write(Json.encode({
    schema_version = 4,
    benchmark = "Kiwi M2.5 terminal write-path benchmark",
    metadata = Environment.collect(timestamp, iterations, warmup),
    configuration = configuration,
    unicode = { version = "17.0.0", grapheme_algorithm = "UAX #29 extended grapheme clusters" },
    results = results,
  }), "\n")
  file:close()
  io.stdout:write("machine-readable result: " .. output .. "\n")
end

if ... == nil then WriteBench.main() end

return WriteBench
