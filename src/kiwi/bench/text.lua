local Environment = require("kiwi.bench.environment")
local FontSystem = require("kiwi.font.system")
local Grapheme = require("kiwi.unicode.grapheme")
local Json = require("kiwi.bench.json")
local Layout = require("kiwi.text.layout")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")
local Stats = require("kiwi.bench.stats")
local Corpus = require("kiwi.text.benchmark_corpus")
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

local workloads = {}
for _, scenario in ipairs(Corpus.scenarios) do workloads[#workloads + 1] = workload(scenario.id, scenario.text) end

local benchmark_shape_options = {
  ligatures = os.getenv("KIWI_LIGATURES") == "1",
  contextual_alternates = os.getenv("KIWI_CALT") == "1",
}

local function new_system(atlas)
  return FontSystem.new({
    pixel_height = 18,
    atlas = atlas or { width = 512, height = 512, max_entries = 1024 },
    ligatures = benchmark_shape_options.ligatures,
    contextual_alternates = benchmark_shape_options.contextual_alternates,
  })
end

function TextBench.font_inventory()
  local system = new_system()
  local fallback_paths = {}
  local seen = {}
  for _, item in ipairs(workloads) do
    for _, cluster in ipairs(Grapheme.segment(item.codepoints)) do
      local face = system:face_for_cluster(cluster)
      if face and face.path ~= system.font_path and not seen[face.path] then
        seen[face.path] = true
        fallback_paths[#fallback_paths + 1] = face.path
      end
    end
  end
  table.sort(fallback_paths)
  local inventory = {
    primary_path = system.font_path,
    pixel_height = system.pixel_height,
    fallback_paths = fallback_paths,
    face_cache_limit = system.face_cache_limit,
    fallback_cache_limit = system.fallback_cache_limit,
  }
  system:destroy()
  return inventory
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
    codepoints = counters.codepoints or 0,
    clusters = counters.clusters or 0,
    runs = counters.runs or 0,
    glyphs = counters.glyphs or 0,
    glyph_instances = counters.glyph_instances or 0,
    logical_dirty_cells = counters.logical_dirty_cells or 0,
    rows_reshaped = counters.rows_reshaped or 0,
    glyph_cache_hits = counters.glyph_cache_hits or 0,
    glyph_cache_misses = counters.glyph_cache_misses or 0,
    fallback_hits = counters.fallback_hits or 0,
    fallback_misses = counters.fallback_misses or 0,
  }
end

local function segmentation(item, iterations, warmup)
  local counters = { codepoints = 0, clusters = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { values = item.codepoints }
  end, function(context)
    context.clusters = Grapheme.segment(context.values)
  end, function(context, recorded)
    if recorded then
      counters.codepoints = counters.codepoints + #context.values
      counters.clusters = counters.clusters + #context.clusters
    end
  end)
  return result("uax29-egc-segmentation", item.name, #item.text, iterations, warmup, timing, memory, counters,
    "UAX #29 extended grapheme segmentation over decoded code points; terminal state, shaping, rasterization, GPU, and presentation excluded")
end

local function width(item, iterations, warmup)
  local counters = { codepoints = 0, clusters = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { values = item.codepoints }
  end, function(context)
    context.clusters = Grapheme.segment(context.values)
    context.columns = 0
    for _, cluster in ipairs(context.clusters) do context.columns = context.columns + Width.columns(cluster) end
  end, function(context, recorded)
    if recorded then
      counters.codepoints = counters.codepoints + #context.values
      counters.clusters = counters.clusters + #context.clusters
    end
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
  local counters = { codepoints = 0, clusters = 0, runs = 0, glyphs = 0, glyph_cache_hits = 0, glyph_cache_misses = 0, fallback_hits = 0, fallback_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { system = new_system() }
  end, function(context)
    context.clusters, context.glyphs = shape_clusters(context.system, item, rasterize)
  end, function(context, recorded)
    if recorded then
      counters.codepoints = counters.codepoints + #item.codepoints
      counters.clusters = counters.clusters + context.clusters
      counters.runs = counters.runs + context.clusters
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
  local system = new_system()
  shape_clusters(system, item, true)
  local counters = { codepoints = 0, clusters = 0, runs = 0, glyphs = 0, glyph_cache_hits = 0, glyph_cache_misses = 0, fallback_hits = 0, fallback_misses = 0 }
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
      counters.codepoints = counters.codepoints + #item.codepoints
      counters.clusters = counters.clusters + context.clusters
      counters.runs = counters.runs + context.clusters
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

local function visible_clusters(state)
  local count = 0
  for row = 0, state.rows - 1 do
    for column = 0, state.columns - 1 do
      local cell = state:get(column, row)
      if cell.codepoints and not cell.continuation then count = count + 1 end
    end
  end
  return count
end

local function layout_cold(item, iterations, warmup)
  local counters = { codepoints = 0, clusters = 0, runs = 0, glyphs = 0, glyph_instances = 0, rows_reshaped = 0, glyph_cache_hits = 0, glyph_cache_misses = 0, fallback_hits = 0, fallback_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local system = new_system()
    local state = State.new(80, 2)
    feed_state(state, item)
    return { system = system, state = state, layout = Layout.new(system) }
  end, function(context)
    context.glyphs = context.layout:update(context.state)
  end, function(context, recorded)
    if recorded then
      counters.codepoints = counters.codepoints + #item.codepoints
      counters.clusters = counters.clusters + visible_clusters(context.state)
      counters.runs = counters.runs + context.layout.stats.runs_reshaped
      counters.glyphs = counters.glyphs + #context.glyphs
      counters.glyph_instances = counters.glyph_instances + #context.glyphs
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
  local system = new_system()
  local state = State.new(80, 2)
  local layout = Layout.new(system)
  feed_state(state, item)
  layout:update(state)
  state.damage:clear()
  local counters = { codepoints = 0, clusters = 0, runs = 0, glyphs = 0, glyph_instances = 0, rows_reshaped = 0, glyph_cache_hits = 0, glyph_cache_misses = 0, fallback_hits = 0, fallback_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { system = system, state = state, layout = layout }
  end, function(context)
    context.glyphs = context.layout:update(context.state)
  end, function(context, recorded)
    if recorded then
      counters.codepoints = counters.codepoints + #item.codepoints
      counters.clusters = counters.clusters + visible_clusters(context.state)
      counters.runs = counters.runs + context.layout.stats.runs_reshaped
      counters.glyphs = counters.glyphs + #context.glyphs
      counters.glyph_instances = counters.glyph_instances + #context.glyphs
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

local function fallback_lookup(kind, iterations, warmup)
  local codepoints = kind == "primary-hit" and { string.byte("A") } or { 0x4e2d }
  local persistent = kind == "cached-fallback-hit" and new_system() or nil
  if persistent then assert(persistent:face_for_cluster(codepoints)) end
  local cleanup = persistent and function() end or function(context)
    context.system:destroy()
  end
  local counters = { codepoints = 0, clusters = 0, fallback_hits = 0, fallback_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    return { system = persistent or new_system() }
  end, function(context)
    context.before_hits = context.system.stats.fallback_hits
    context.before_misses = context.system.stats.fallback_misses
    context.face = context.system:face_for_cluster(codepoints)
  end, function(context, recorded)
    if recorded then
      counters.codepoints = counters.codepoints + #codepoints
      counters.clusters = counters.clusters + 1
      counters.fallback_hits = counters.fallback_hits + context.system.stats.fallback_hits - context.before_hits
      counters.fallback_misses = counters.fallback_misses + context.system.stats.fallback_misses - context.before_misses
      assert(context.face ~= nil, kind .. " unexpectedly missed")
    end
  end, cleanup)
  if persistent then persistent:destroy() end
  return result("font-fallback-" .. kind, kind, #codepoints, iterations, warmup, timing, memory, counters,
    kind == "cached-fallback-hit"
      and "Persistent Fontconfig fallback decision lookup after one initial CJK resolution; shaping, rasterization, GPU, and presentation excluded"
      or "Font face coverage and fallback lookup against a fresh pre-created text system; shaping, rasterization, GPU, and presentation excluded")
end

local function glyph_cache_lookup(kind, iterations, warmup)
  local persistent = kind == "hit" and new_system() or nil
  local function insert(system, capacity_path)
    local face = assert(system:face_for_cluster({ string.byte("A") }))
    local glyph = assert(system.glyph_cache:get_or_insert(face, face:glyph_index(string.byte("A"))))
    if capacity_path then
      assert(system.glyph_cache:get_or_insert(face, face:glyph_index(string.byte("B"))))
      return system.glyph_cache:get_or_insert(face, face:glyph_index(string.byte("C")))
    end
    return glyph
  end
  if persistent then insert(persistent, false) end
  local cleanup = persistent and function() end or function(context)
    context.system:destroy()
  end
  local counters = { codepoints = 0, glyphs = 0, glyph_cache_hits = 0, glyph_cache_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local atlas = { width = 512, height = 512, max_entries = kind == "bounded-capacity" and 2 or 1024 }
    return { system = persistent or new_system(atlas) }
  end, function(context)
    context.before_hits = context.system.glyph_cache.stats.hits
    context.before_misses = context.system.glyph_cache.stats.misses
    context.glyph, context.reason = insert(context.system, kind == "bounded-capacity")
  end, function(context, recorded)
    if recorded then
      counters.codepoints = counters.codepoints + 1
      counters.glyphs = counters.glyphs + 1
      counters.glyph_cache_hits = counters.glyph_cache_hits + context.system.glyph_cache.stats.hits - context.before_hits
      counters.glyph_cache_misses = counters.glyph_cache_misses + context.system.glyph_cache.stats.misses - context.before_misses
      if kind == "bounded-capacity" then
        assert(context.glyph == nil and context.reason == "entry-limit", "bounded glyph cache did not reject deterministically")
      else
        assert(context.glyph ~= nil, "glyph cache " .. kind .. " did not return glyph")
      end
    end
  end, cleanup)
  if persistent then persistent:destroy() end
  return result("glyph-atlas-" .. kind, kind, 1, iterations, warmup, timing, memory, counters,
    kind == "hit" and "Persistent glyph-ID alpha-atlas cache hit; rasterization, GPU upload, and presentation excluded"
      or kind == "bounded-capacity" and "Fresh bounded single-page glyph-ID atlas filled to its entry limit; deterministic rejection is timed"
      or "Fresh glyph-ID cache miss including FreeType rasterization and alpha-atlas insertion; GPU upload and presentation excluded")
end

local function layout_edit(name, initial, extension, iterations, warmup)
  local counters = { codepoints = 0, clusters = 0, runs = 0, glyphs = 0, glyph_instances = 0, rows_reshaped = 0, logical_dirty_cells = 0, glyph_cache_hits = 0, glyph_cache_misses = 0, fallback_hits = 0, fallback_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local system = new_system()
    local state = State.new(80, 2)
    local layout = Layout.new(system)
    feed_state(state, initial)
    layout:update(state)
    state.damage:clear()
    return { system = system, state = state, layout = layout }
  end, function(context)
    feed_state(context.state, extension)
    context.logical_dirty_cells = context.state.damage.dirty_count
    context.glyphs = context.layout:update(context.state)
  end, function(context, recorded)
    if recorded then
      counters.codepoints = counters.codepoints + #extension.codepoints
      counters.clusters = counters.clusters + visible_clusters(context.state)
      counters.runs = counters.runs + context.layout.stats.runs_reshaped
      counters.glyphs = counters.glyphs + #context.glyphs
      counters.glyph_instances = counters.glyph_instances + #context.glyphs
      counters.rows_reshaped = counters.rows_reshaped + context.layout.stats.rows_reshaped
      counters.logical_dirty_cells = counters.logical_dirty_cells + context.logical_dirty_cells
      counters.glyph_cache_hits = counters.glyph_cache_hits + context.system.glyph_cache.stats.hits
      counters.glyph_cache_misses = counters.glyph_cache_misses + context.system.glyph_cache.stats.misses
      counters.fallback_hits = counters.fallback_hits + context.system.stats.fallback_hits
      counters.fallback_misses = counters.fallback_misses + context.system.stats.fallback_misses
    end
  end, function(context)
    context.system:destroy()
  end)
  return result("text-row-layout-edit", name, #extension.text, iterations, warmup, timing, memory, counters,
    "One semantic text edit followed by affected-row shaping, glyph lookup, and glyph-instance generation; GPU upload and presentation excluded")
end

local function full_text_pipeline(item, iterations, warmup)
  local counters = { codepoints = 0, clusters = 0, runs = 0, glyphs = 0, glyph_instances = 0, rows_reshaped = 0, logical_dirty_cells = 0, glyph_cache_hits = 0, glyph_cache_misses = 0, fallback_hits = 0, fallback_misses = 0 }
  local timing, memory = measure(iterations, warmup, function()
    local system = new_system()
    local state = State.new(80, 2)
    return { system = system, state = state, parser = Parser.new(state), layout = Layout.new(system) }
  end, function(context)
    context.parser:feed(item.text)
    context.parser:finish()
    context.logical_dirty_cells = context.state.damage.dirty_count
    context.glyphs = context.layout:update(context.state)
  end, function(context, recorded)
    if recorded then
      counters.codepoints = counters.codepoints + #item.codepoints
      counters.clusters = counters.clusters + visible_clusters(context.state)
      counters.runs = counters.runs + context.layout.stats.runs_reshaped
      counters.glyphs = counters.glyphs + #context.glyphs
      counters.glyph_instances = counters.glyph_instances + #context.glyphs
      counters.rows_reshaped = counters.rows_reshaped + context.layout.stats.rows_reshaped
      counters.logical_dirty_cells = counters.logical_dirty_cells + context.logical_dirty_cells
      counters.glyph_cache_hits = counters.glyph_cache_hits + context.system.glyph_cache.stats.hits
      counters.glyph_cache_misses = counters.glyph_cache_misses + context.system.glyph_cache.stats.misses
      counters.fallback_hits = counters.fallback_hits + context.system.stats.fallback_hits
      counters.fallback_misses = counters.fallback_misses + context.system.stats.fallback_misses
    end
  end, function(context)
    context.system:destroy()
  end)
  return result("full-text-cluster-to-glyph-instance", item.name, #item.text, iterations, warmup, timing, memory, counters,
    "Production parser direct print sink through grapheme state, terminal width, row shaping, fallback, glyph-ID cache, and Lua glyph-instance generation; GPU queue writes, execution, and presentation excluded")
end

function TextBench.run(iterations, warmup)
  iterations = iterations or 10
  warmup = warmup or 3
  local results = {
    segmentation = {},
    width = {},
    shaping_cold = {},
    shaping_hot = {},
    fallback = {},
    glyph_atlas = {},
    layout_cold = {},
    layout_cached = {},
    layout_edit = {},
    full_text_pipeline = {},
  }
  for _, item in ipairs(workloads) do
    results.segmentation[#results.segmentation + 1] = segmentation(item, iterations, warmup)
    results.width[#results.width + 1] = width(item, iterations, warmup)
    results.shaping_cold[#results.shaping_cold + 1] = shaping(item, iterations, warmup, false)
    results.shaping_hot[#results.shaping_hot + 1] = shaping_hot(item, iterations, warmup)
    results.layout_cold[#results.layout_cold + 1] = layout_cold(item, iterations, warmup)
    results.layout_cached[#results.layout_cached + 1] = layout_cached(item, iterations, warmup)
    results.full_text_pipeline[#results.full_text_pipeline + 1] = full_text_pipeline(item, iterations, warmup)
  end
  for _, kind in ipairs({ "primary-hit", "initial-fallback-resolution", "cached-fallback-hit" }) do
    results.fallback[#results.fallback + 1] = fallback_lookup(kind, iterations, warmup)
  end
  for _, kind in ipairs({ "miss", "hit", "bounded-capacity" }) do
    results.glyph_atlas[#results.glyph_atlas + 1] = glyph_cache_lookup(kind, iterations, warmup)
  end
  for _, item in ipairs(workloads) do
    results.layout_edit[#results.layout_edit + 1] = layout_edit(item.name, workload(item.name .. "-base", ""), item, iterations, warmup)
  end
  return results
end

function TextBench.print_results(results)
  for _, layer in ipairs({ "segmentation", "width", "shaping_cold", "shaping_hot", "fallback", "glyph_atlas", "layout_cold", "layout_cached", "layout_edit", "full_text_pipeline" }) do
    for _, item in ipairs(results[layer]) do
      io.stdout:write(string.format(
        "m2 %-33s %-26s iterations=%d cpu mean=%.4fms p50=%.4fms p95=%.4fms p99=%.4fms cp=%d clusters=%d runs=%d glyphs=%d instances=%d dirty=%d cache=%d/%d fallback=%d/%d heap retained=%.1f KiB peak=%.1f KiB\n",
        item.component, item.workload, item.iterations, item.cpu_ms.mean, item.cpu_ms.p50, item.cpu_ms.p95, item.cpu_ms.p99,
        item.codepoints, item.clusters, item.runs, item.glyphs, item.glyph_instances, item.logical_dirty_cells,
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
    schema_version = 2,
    benchmark = "Kiwi M2 native text benchmark",
    metadata = Environment.collect(timestamp, iterations, warmup),
    corpus = { version = Corpus.version, scenarios = Corpus.scenarios },
    font = TextBench.font_inventory(),
    shape_options = benchmark_shape_options,
    unicode = { version = "17.0.0", grapheme_algorithm = "UAX #29 extended grapheme clusters", width_policy = Width.policy_version },
    results = results,
  }), "\n")
  file:close()
  io.stdout:write("machine-readable result: " .. output .. "\n")
end

if ... == nil then TextBench.main() end

return TextBench
