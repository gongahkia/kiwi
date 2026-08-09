local Environment = require("kiwi.bench.environment")
local FontSystem = require("kiwi.font.system")
local Grapheme = require("kiwi.unicode.grapheme")
local Json = require("kiwi.bench.json")
local Layout = require("kiwi.text.layout")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")
local Stats = require("kiwi.bench.stats")
local Utf8 = require("kiwi.terminal.utf8")
local Width = require("kiwi.terminal.width")

local TextBench = {}

local function number_from_env(name, fallback)
  local value = tonumber(os.getenv(name))
  return value and value > 0 and math.floor(value) or fallback
end

local function codepoints(text)
  local values = {}
  local decoder = Utf8.Decoder.new(function(codepoint)
    values[#values + 1] = codepoint
  end)
  for index = 1, #text do decoder:feed_byte(text:byte(index)) end
  decoder:finish()
  return values
end

local function text_from(values)
  local parts = {}
  for index, codepoint in ipairs(values) do parts[index] = Utf8.encode(codepoint) end
  return table.concat(parts)
end

local function workload(name, values)
  local text = type(values) == "string" and values or text_from(values)
  return { name = name, text = text, codepoints = codepoints(text) }
end

local workloads = {
  workload("ascii", "Kiwi terminal text 123"),
  workload("combining", { 0x43, 0x61, 0x66, 0x65, 0x301, 0x20, 0x6f, 0x308 }),
  workload("cjk", { 0x4e2d, 0x6587, 0x6f22, 0x5b57, 0x20, 0x304b, 0x306a }),
  workload("emoji", { 0x1f469, 0x200d, 0x1f680, 0x20, 0x1f1f8, 0x1f1ec, 0x20, 0x2764, 0xfe0f }),
  workload("mixed", { 0x4b, 0x69, 0x77, 0x69, 0x20, 0x65, 0x301, 0x20, 0x4e2d, 0x20, 0x1f469, 0x200d, 0x1f680, 0x20, 0xe0b0 }),
}

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

local function result(component, workload_name, input_bytes, iterations, warmup, timing, memory, counters, scope)
  local seconds = timing.total / 1000
  return {
    component = component,
    workload = workload_name,
    scope = scope,
    input_bytes_per_iteration = input_bytes,
    iterations = iterations,
    warmup_iterations = warmup,
    throughput_bytes_per_second = seconds > 0 and input_bytes * iterations / seconds or 0,
    cpu_ms = timing,
    memory = memory,
    clusters = counters.clusters or 0,
    glyphs = counters.glyphs or 0,
    rows_reshaped = counters.rows_reshaped or 0,
    glyph_cache_hits = counters.glyph_cache_hits or 0,
    glyph_cache_misses = counters.glyph_cache_misses or 0,
    fallback_hits = counters.fallback_hits or 0,
    fallback_misses = counters.fallback_misses or 0,
  }
end

local function segmentation(item, iterations, warmup)
  local counters = { clusters = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { values = item.codepoints }
  end, function(context)
    context.clusters = Grapheme.segment(context.values)
  end, function(context, recorded)
    if recorded then counters.clusters = counters.clusters + #context.clusters end
  end)
  return result("uax29-egc-segmentation", item.name, #item.text, iterations, warmup, timing, memory, counters,
    "UAX #29 extended grapheme segmentation over decoded code points; terminal state, shaping, rasterization, GPU, and presentation excluded")
end

local function width(item, iterations, warmup)
  local counters = { clusters = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { values = item.codepoints }
  end, function(context)
    context.clusters = Grapheme.segment(context.values)
    context.columns = 0
    for _, cluster in ipairs(context.clusters) do context.columns = context.columns + Width.columns(cluster) end
  end, function(context, recorded)
    if recorded then counters.clusters = counters.clusters + #context.clusters end
  end)
  return result("terminal-width-policy", item.name, #item.text, iterations, warmup, timing, memory, counters,
    "UAX #29 segmentation plus Kiwi M2 width policy; terminal state, font fallback, shaping, rasterization, GPU, and presentation excluded")
end

local function shape_clusters(system, item, rasterize)
  local clusters = Grapheme.segment(item.codepoints)
  local glyphs = 0
  for _, cluster in ipairs(clusters) do
    local face = system:face_for_cluster(cluster)
    if face then
      local shaped = face:shape(text_from(cluster), system.shape_options)
      glyphs = glyphs + #shaped
      if rasterize then
        for _, glyph in ipairs(shaped) do system.glyph_cache:get_or_insert(face, glyph.glyph_id) end
      end
    end
  end
  return #clusters, glyphs
end

local function shaping(item, iterations, warmup, rasterize)
  local counters = { clusters = 0, glyphs = 0, glyph_cache_hits = 0, glyph_cache_misses = 0, fallback_hits = 0, fallback_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { system = FontSystem.new({ pixel_height = 18, atlas = { width = 512, height = 512, max_entries = 1024 } }) }
  end, function(context)
    context.clusters, context.glyphs = shape_clusters(context.system, item, rasterize)
  end, function(context, recorded)
    if recorded then
      counters.clusters = counters.clusters + context.clusters
      counters.glyphs = counters.glyphs + context.glyphs
      counters.glyph_cache_hits = counters.glyph_cache_hits + context.system.glyph_cache.stats.hits
      counters.glyph_cache_misses = counters.glyph_cache_misses + context.system.glyph_cache.stats.misses
      counters.fallback_hits = counters.fallback_hits + context.system.stats.fallback_hits
      counters.fallback_misses = counters.fallback_misses + context.system.stats.fallback_misses
    end
  end, function(context)
    context.system:destroy()
  end)
  return result(rasterize and "harfbuzz-shape-glyph-cache-cold" or "harfbuzz-shape-cold", item.name, #item.text, iterations, warmup, timing, memory, counters,
    rasterize and "Fresh Fontconfig, FreeType, HarfBuzz, fallback, and glyph-cache objects per iteration; atlas GPU upload and presentation excluded"
      or "Fresh Fontconfig, FreeType, HarfBuzz, and fallback objects per iteration; glyph rasterization, atlas insertion, GPU, and presentation excluded")
end

local function shaping_hot(item, iterations, warmup)
  local system = FontSystem.new({ pixel_height = 18, atlas = { width = 512, height = 512, max_entries = 1024 } })
  shape_clusters(system, item, true)
  local counters = { clusters = 0, glyphs = 0, glyph_cache_hits = 0, glyph_cache_misses = 0, fallback_hits = 0, fallback_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { system = system }
  end, function(context)
    context.before = {
      glyph_cache_hits = context.system.glyph_cache.stats.hits,
      glyph_cache_misses = context.system.glyph_cache.stats.misses,
      fallback_hits = context.system.stats.fallback_hits,
      fallback_misses = context.system.stats.fallback_misses,
    }
    context.clusters, context.glyphs = shape_clusters(context.system, item, true)
  end, function(context, recorded)
    if recorded then
      counters.clusters = counters.clusters + context.clusters
      counters.glyphs = counters.glyphs + context.glyphs
      counters.glyph_cache_hits = counters.glyph_cache_hits + context.system.glyph_cache.stats.hits - context.before.glyph_cache_hits
      counters.glyph_cache_misses = counters.glyph_cache_misses + context.system.glyph_cache.stats.misses - context.before.glyph_cache_misses
      counters.fallback_hits = counters.fallback_hits + context.system.stats.fallback_hits - context.before.fallback_hits
      counters.fallback_misses = counters.fallback_misses + context.system.stats.fallback_misses - context.before.fallback_misses
    end
  end)
  system:destroy()
  return result("harfbuzz-shape-glyph-cache-hot", item.name, #item.text, iterations, warmup, timing, memory, counters,
    "Persistent Fontconfig, FreeType, HarfBuzz, fallback cache, and prepopulated glyph cache; atlas GPU upload and presentation excluded")
end

local function feed_state(state, item)
  local parser = Parser.new(state)
  parser:feed(item.text)
  parser:finish()
end

local function layout_cold(item, iterations, warmup)
  local counters = { glyphs = 0, rows_reshaped = 0, glyph_cache_hits = 0, glyph_cache_misses = 0, fallback_hits = 0, fallback_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local system = FontSystem.new({ pixel_height = 18, atlas = { width = 512, height = 512, max_entries = 1024 } })
    local state = State.new(80, 2)
    feed_state(state, item)
    return { system = system, state = state, layout = Layout.new(system) }
  end, function(context)
    context.glyphs = context.layout:update(context.state)
  end, function(context, recorded)
    if recorded then
      counters.glyphs = counters.glyphs + #context.glyphs
      counters.rows_reshaped = counters.rows_reshaped + context.layout.stats.rows_reshaped
      counters.glyph_cache_hits = counters.glyph_cache_hits + context.system.glyph_cache.stats.hits
      counters.glyph_cache_misses = counters.glyph_cache_misses + context.system.glyph_cache.stats.misses
      counters.fallback_hits = counters.fallback_hits + context.system.stats.fallback_hits
      counters.fallback_misses = counters.fallback_misses + context.system.stats.fallback_misses
    end
  end, function(context)
    context.system:destroy()
  end)
  return result("text-row-layout-cold", item.name, #item.text, iterations, warmup, timing, memory, counters,
    "Fresh state, Fontconfig, FreeType, HarfBuzz, fallback, row layout, and glyph cache; GPU upload and presentation excluded")
end

local function layout_cached(item, iterations, warmup)
  local system = FontSystem.new({ pixel_height = 18, atlas = { width = 512, height = 512, max_entries = 1024 } })
  local state = State.new(80, 2)
  local layout = Layout.new(system)
  feed_state(state, item)
  layout:update(state)
  state.damage:clear()
  local counters = { glyphs = 0, rows_reshaped = 0, glyph_cache_hits = 0, glyph_cache_misses = 0, fallback_hits = 0, fallback_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { system = system, state = state, layout = layout }
  end, function(context)
    context.glyphs = context.layout:update(context.state)
  end, function(context, recorded)
    if recorded then
      counters.glyphs = counters.glyphs + #context.glyphs
      counters.rows_reshaped = counters.rows_reshaped + context.layout.stats.rows_reshaped
      counters.glyph_cache_hits = counters.glyph_cache_hits + context.system.glyph_cache.stats.hits
      counters.glyph_cache_misses = counters.glyph_cache_misses + context.system.glyph_cache.stats.misses
      counters.fallback_hits = counters.fallback_hits + context.system.stats.fallback_hits
      counters.fallback_misses = counters.fallback_misses + context.system.stats.fallback_misses
    end
  end)
  system:destroy()
  return result("text-row-layout-cached", item.name, #item.text, iterations, warmup, timing, memory, counters,
    "Persistent already-shaped rows with no logical text damage; glyph cache, GPU upload, and presentation are excluded from the steady-state cache-hit path")
end

function TextBench.run(iterations, warmup)
  iterations = iterations or 10
  warmup = warmup or 3
  local results = { segmentation = {}, width = {}, shaping_cold = {}, shaping_hot = {}, layout_cold = {}, layout_cached = {} }
  for _, item in ipairs(workloads) do
    results.segmentation[#results.segmentation + 1] = segmentation(item, iterations, warmup)
    results.width[#results.width + 1] = width(item, iterations, warmup)
    results.shaping_cold[#results.shaping_cold + 1] = shaping(item, iterations, warmup, false)
    results.shaping_hot[#results.shaping_hot + 1] = shaping_hot(item, iterations, warmup)
    results.layout_cold[#results.layout_cold + 1] = layout_cold(item, iterations, warmup)
    results.layout_cached[#results.layout_cached + 1] = layout_cached(item, iterations, warmup)
  end
  return results
end

function TextBench.print_results(results)
  for _, layer in ipairs({ "segmentation", "width", "shaping_cold", "shaping_hot", "layout_cold", "layout_cached" }) do
    for _, item in ipairs(results[layer]) do
      io.stdout:write(string.format(
        "m2 %-33s %-10s iterations=%d cpu mean=%.4fms p95=%.4fms glyphs=%d clusters=%d cache=%d/%d fallback=%d/%d heap retained=%.1f KiB peak=%.1f KiB\n",
        item.component, item.workload, item.iterations, item.cpu_ms.mean, item.cpu_ms.p95, item.glyphs, item.clusters,
        item.glyph_cache_hits, item.glyph_cache_misses, item.fallback_hits, item.fallback_misses,
        item.memory.retained_kib_delta, item.memory.peak_kib_delta
      ))
    end
  end
end

function TextBench.main()
  local iterations = number_from_env("KIWI_TEXT_BENCH_ITERATIONS", 10)
  local warmup = number_from_env("KIWI_TEXT_BENCH_WARMUP", 3)
  local results = TextBench.run(iterations, warmup)
  TextBench.print_results(results)
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local output = "bench/results/" .. timestamp .. "-text.json"
  local file, message = io.open(output, "wb")
  if not file then error("Unable to create " .. output .. ": " .. message .. ". Run through make bench-text so the results directory exists.") end
  file:write(Json.encode({
    schema_version = 1,
    benchmark = "Kiwi M2 native text benchmark",
    metadata = Environment.collect(timestamp, iterations, warmup),
    unicode = { version = "17.0.0", grapheme_algorithm = "UAX #29 extended grapheme clusters", width_policy = Width.policy_version },
    results = results,
  }), "\n")
  file:close()
  io.stdout:write("machine-readable result: " .. output .. "\n")
end

if ... == nil then TextBench.main() end

return TextBench
