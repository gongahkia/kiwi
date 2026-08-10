local Environment = require("kiwi.bench.environment")
local FontSystem = require("kiwi.font.system")
local Json = require("kiwi.bench.json")
local Stats = require("kiwi.bench.stats")
local TextBench = require("kiwi.bench.text")
local Corpus = require("kiwi.text.benchmark_corpus")
local CorpusReview = require("kiwi.bench.text_corpus")
local Backend = require("kiwi.text.backend")
local Lab = require("kiwi.text.lab")
local Parser = require("kiwi.terminal.parser")
local State = require("kiwi.terminal.state")

local TextLab = {
  max_iterations = 10,
}

local function number_from_env(name, fallback)
  local value = os.getenv(name)
  if value == nil or #value == 0 then return fallback end
  local number = tonumber(value)
  assert(number and number > 0 and number % 1 == 0 and number <= TextLab.max_iterations,
    name .. " must be a positive integer no greater than " .. TextLab.max_iterations)
  return number
end

local function shape_options()
  return {
    ligatures = os.getenv("KIWI_LIGATURES") == "1",
    contextual_alternates = os.getenv("KIWI_CALT") == "1",
  }
end

local function new_system(options)
  return FontSystem.new({
    pixel_height = 18,
    atlas = { width = 512, height = 512, max_entries = 1024 },
    ligatures = options.ligatures,
    contextual_alternates = options.contextual_alternates,
  })
end

local function execute(scenario, requested, options)
  local system = new_system(options)
  local backend = Backend.create(system, { requested = requested })
  local state = State.new(80, 2)
  local parser = Parser.new(state)
  parser:feed(scenario.text)
  parser:finish()
  local started = os.clock()
  local glyphs = backend:update(state)
  local elapsed = (os.clock() - started) * 1000
  local layout = backend:layout()
  local result = {
    cpu_ms = elapsed,
    glyph_instances = #glyphs,
    rows_reshaped = layout.stats.rows_reshaped,
    runs_reshaped = layout.stats.runs_reshaped,
    glyphs_produced = layout.stats.glyphs_produced,
    fallback_hits = system.stats.fallback_hits,
    fallback_misses = system.stats.fallback_misses,
    descriptor = backend:descriptor(),
  }
  backend:destroy()
  system:destroy()
  return result
end

function TextLab.measure_backend(requested, iterations, warmup, options)
  local scenarios = {}
  for index, scenario in ipairs(Corpus.scenarios) do
    for _ = 1, warmup do execute(scenario, requested, options) end
    local samples = {}
    local totals = {
      fallback_hits = 0,
      fallback_misses = 0,
      glyph_instances = 0,
      glyphs_produced = 0,
      rows_reshaped = 0,
      runs_reshaped = 0,
    }
    local descriptor
    for iteration = 1, iterations do
      local item = execute(scenario, requested, options)
      samples[iteration] = item.cpu_ms
      descriptor = item.descriptor
      for key, value in pairs(totals) do totals[key] = value + item[key] end
    end
    scenarios[index] = {
      id = scenario.id,
      input_bytes = #scenario.text,
      iterations = iterations,
      warmup_iterations = warmup,
      cpu_ms = Stats.summary(samples),
      counters = totals,
      descriptor = descriptor,
      scope = "backend:update after parser/state setup; CPU row shaping and glyph-cache work included; parser, WGPU queue writes, GPU execution, compositor, and presentation excluded",
    }
  end
  return scenarios
end

local function backend_entry(requested, descriptor, measurements)
  local available = descriptor.active == requested and not descriptor.fallback
  return {
    requested = requested,
    active = descriptor.active,
    availability = available and "available" or "unavailable",
    fallback = descriptor.fallback,
    fallback_reason = descriptor.fallback_reason,
    descriptor = descriptor,
    measurements = measurements,
    visual_review_command = "KIWI_TEXT_LAB=1 KIWI_TEXT_LAB_BACKEND=" .. requested .. " KIWI_MAX_FRAMES=240 make text-corpus-demo",
  }
end

function TextLab.report(options)
  options = options or {}
  local iterations = options.iterations or 1
  local warmup = options.warmup or 0
  assert(type(iterations) == "number" and iterations > 0 and iterations % 1 == 0 and iterations <= TextLab.max_iterations,
    "text laboratory iterations must be a positive integer within the bound")
  assert(type(warmup) == "number" and warmup >= 0 and warmup % 1 == 0 and warmup <= TextLab.max_iterations,
    "text laboratory warmup must be a non-negative integer within the bound")
  local requested = Lab.with_baseline(options.backends or Lab.parse_backends(os.getenv("KIWI_TEXT_LAB_BACKENDS")))
  local describe = options.describe or TextBench.backend_descriptor
  local measure = options.measure or function(name)
    return TextLab.measure_backend(name, iterations, warmup, shape_options())
  end
  local backends = {}
  local unavailable = {}
  for index, name in ipairs(requested) do
    local descriptor = describe(name)
    local measurements = measure(name, descriptor)
    local entry = backend_entry(name, descriptor, measurements)
    backends[index] = entry
    if entry.availability == "unavailable" then
      unavailable[#unavailable + 1] = {
        requested = entry.requested,
        active = entry.active,
        fallback_reason = entry.fallback_reason,
      }
    end
  end
  local corpus = options.corpus or CorpusReview.manifest()
  local metadata = options.metadata or Environment.collect(options.timestamp or os.date("!%Y%m%dT%H%M%SZ"), iterations, warmup)
  local font = options.font or TextBench.font_inventory()
  return {
    schema_version = 1,
    artifact = "Kiwi M8 text laboratory report",
    metadata = metadata,
    corpus = corpus,
    font = font,
    shape_options = shape_options(),
    backends = backends,
    report = {
      measured_facts = {
        cpu_scope = "Each backend record contains bounded per-corpus CPU samples for backend:update; GPU and presentation are excluded.",
        semantic_contract = "The shared corpus manifest and backend descriptor are recorded for every requested backend.",
      },
      unavailable_environments = unavailable,
      inference = {
        "This report does not infer visual quality or promotion from CPU samples.",
        "A fallback descriptor is baseline behavior, not evidence that the requested prototype ran.",
      },
      recommendation = {
        status = #unavailable == 0 and "manual-review-required" or "prototype-unavailable",
        rationale = #unavailable == 0
          and "Review matching native screenshots, semantic counters, and same-host measurements before a promotion decision."
          or "One or more requests used the explicit atlas fallback; no prototype comparison is available for those requests.",
      },
      visual_review = {
        status = "manual-required",
        criteria = "Compare screenshots for missing glyphs, overlap, clipping, wide-cell occupancy, fallback changes, ligature behavior, and dense UI alignment.",
      },
      promotion_exit_criteria = {
        "same corpus, font inventory, shaping options, content scale, and host configuration",
        "no terminal-width, grapheme ownership, or terminal-column mapping change",
        "bounded resource and lifecycle tests plus an observable atlas fallback",
        "native visual review and make check pass",
      },
      retirement_exit_criteria = {
        "prototype has a documented unavailable/failure fallback or is removed from the laboratory list",
        "the atlas baseline remains selectable and its artifacts remain reproducible",
      },
    },
  }
end

function TextLab.main()
  local iterations = number_from_env("KIWI_TEXT_LAB_ITERATIONS", 1)
  local warmup = number_from_env("KIWI_TEXT_LAB_WARMUP", 0)
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local output = os.getenv("KIWI_TEXT_LAB_ARTIFACT") or "bench/results/" .. timestamp .. "-text-lab.json"
  local report = TextLab.report({ iterations = iterations, warmup = warmup, timestamp = timestamp })
  local file, message = io.open(output, "wb")
  if not file then error("Unable to create " .. output .. ": " .. message .. ". Run through make text-lab so the results directory exists.") end
  file:write(Json.encode(report), "\n")
  file:close()
  for _, backend in ipairs(report.backends) do
    io.stdout:write(string.format("text-lab requested=%s active=%s availability=%s fallback=%s\n",
      backend.requested, backend.active, backend.availability, tostring(backend.fallback)))
  end
  io.stdout:write("text laboratory report: ", output, "\n")
end

if ... == nil then TextLab.main() end

return TextLab
